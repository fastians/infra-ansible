# CLAUDE.md - Infra Ansible Engineering Standard

This document is the operating contract for `infra_ansible`.

## Goals

- Keep provisioning deterministic and repeatable.
- Minimize production risk during updates (use `--limit` per tier/host).
- Keep host targeting explicit and auditable.
- Keep secrets out of git-tracked plaintext files.

## Source of Truth

- Inventory: `inventories/prod/hosts.ini`
- Host-specific overrides: `inventories/prod/host_vars/*.yml`
- Shared environment config: `inventories/prod/group_vars/**/*.yml`
- Main orchestration: `site.yml`
- Day-2 wrapper: `./scripts/provision` (run with `bash ./scripts/provision` if execute bit is missing)

## Deployment tiers (inventory)

Three parallel app tiers; **never assume a single “prod” host**.

| Tier | Ansible hosts | Terraform | Public DNS (when cut over) |
|------|---------------|-----------|----------------------------|
| **GCP legacy** | `backend-server`, `salome-server` | (existing GCP) | Legacy IPs |
| **AWS staging** | `backend-aws-staging`, `salome-aws-staging` | `aws-app-staging` | Staging IPs only |
| **AWS production** | `backend-aws-prod`, `salome-aws-prod` (+ optional `geo-aws-prod`, `llm-aws-prod`) | `aws-app-production` | `api.mek-lab.com`, `salome.mek-lab.com` |

**Production API routing** (single public host `api.mek-lab.com`):

| Path | Service | Typical upstream |
|------|---------|------------------|
| `/` | backendserver :8000 | localhost on API host |
| `/geo/` | geoserver :8001 | localhost (all-in-one) or GEO host private IP |
| `/llm/` | llmserver :8002 | localhost (all-in-one) or LLM host private IP |

Set `nginx_geo_upstream`, `nginx_llm_upstream`, `geo_server_internal_url`, `llm_server_internal_url` in `host_vars/backend-aws-prod.yml` when split — see `host_vars/backend-aws-prod-split.example.yml`.

Groups `[backend]` and `[salome]` include **both** staging and production children. Always use `--limit <hostname>` so `site.yml` does not touch every tier at once.

Constants: `inventories/prod/group_vars/all/site_constants.yml` (`api_public_host`, `salome_public_host`).

## Required Runtime Pattern

- Run via `./scripts/provision <host>` (or `ansible-playbook` with `--limit`).
- Sync secrets before provision: `bash ./scripts/sync-env-production.sh` (builds gitignored `.env.production` from `zz_secrets.local.yml`).
- Prefer `inventories/prod/group_vars/all/zz_secrets.local.yml` (gitignored) for vault overrides; template: `zz_secrets.local.example.yml`.
- `inventories/prod/group_vars/all/secrets.yml` uses `lookup('env', 'VAULT_*')` — populated by `.env.production` when scripts load it.
- Default script profile: `.env.production`; use `APP_ENV=local` for `.env.local` only.

### Provision examples

```bash
cd infra_ansible
bash ./scripts/sync-env-production.sh

# AWS production (public traffic)
bash ./scripts/provision backend-aws-prod
bash ./scripts/provision salome-aws-prod

# AWS staging (pre-prod validation)
bash ./scripts/provision backend-aws-staging
bash ./scripts/provision salome-aws-staging

# GCP legacy
bash ./scripts/provision backend-server
bash ./scripts/provision salome-server

# Monitoring (unchanged)
bash ./scripts/provision monitoring-server
```

Narrow playbooks:

```bash
ansible-playbook -i inventories/prod/hosts.ini playbooks/site-backend-apps.yml --limit backend-aws-prod
ansible-playbook -i inventories/prod/hosts.ini playbooks/site-geo-apps.yml --limit geo-aws-prod
ansible-playbook -i inventories/prod/hosts.ini playbooks/site-llm-apps.yml --limit llm-aws-prod
ansible-playbook -i inventories/prod/hosts.ini playbooks/site-salome-apps.yml --limit salome-aws-prod -v
```

## Split microservices migration (step-by-step)

Current production can stay **all-in-one** (`backend-aws-prod` runs all three apps). To move to dedicated GEO/LLM hosts:

1. **Terraform** — in `aws-app-production/terraform.tfvars` set `enable_split_microservices = true`, apply, note `geo_private_ip` / `llm_private_ip`.
2. **Inventory** — uncomment `geo-aws-prod` / `llm-aws-prod` in `hosts.ini` with public IPs from `terraform output`.
3. **Provision GEO + LLM** — base agents, deploy key, then:
   ```bash
   ansible-playbook -i inventories/prod/hosts.ini playbooks/site-geo-apps.yml --limit geo-aws-prod
   ansible-playbook -i inventories/prod/hosts.ini playbooks/site-llm-apps.yml --limit llm-aws-prod
   ```
4. **Cut over API host** — merge `host_vars/backend-aws-prod-split.example.yml` into `backend-aws-prod.yml` (private upstream URLs, `python_apps` backend-only).
5. **Redeploy backend + nginx** (with `backend_split_microservices: true` in host_vars, playbook removes GEO/LLM repos, systemd units, and miniconda from the API host):
   ```bash
   ansible-playbook -i inventories/prod/hosts.ini playbooks/site-backend-apps.yml --limit backend-aws-prod
   ```
6. **Verify** — `curl https://api.mek-lab.com/geo/docs`, `curl https://api.mek-lab.com/llm/docs`, load-cad from UI.

Frontend URLs stay `https://api.mek-lab.com/geo` and `/llm` — no subdomain change required.

## New production host checklist

After Terraform creates VMs (`infra_terraform/environments/aws-app-production`):

1. **Inventory** — `hosts.ini` already lists `backend-aws-prod` / `salome-aws-prod`; confirm `ansible_host` matches `terraform output`.
2. **GitHub deploy key** — copy `/home/mateen_fastians/.ssh` from staging to prod (Ansible does not create this automatically):
   ```bash
   # From control machine (example)
   ssh ubuntu@<staging-ip> 'sudo tar cf - -C /home/mateen_fastians .ssh' | \
   ssh ubuntu@<prod-ip> 'sudo mkdir -p /home/mateen_fastians && sudo tar xf - -C /home/mateen_fastians && sudo chown -R mateen_fastians:mateen_fastians /home/mateen_fastians/.ssh && sudo chmod 700 /home/mateen_fastians/.ssh && sudo chmod 600 /home/mateen_fastians/.ssh/id_ed25519'
   ```
3. **Provision** — `bash ./scripts/provision backend-aws-prod` (and salome).
4. **PostgreSQL** (backend only, on-VM today) — not in Terraform; install Postgres, create DB/user matching `vault_backend_database_url`, then:
   ```bash
   ansible-playbook -i inventories/prod/hosts.ini playbooks/seed.yml \
     -e service=backendserver -e target=backend-aws-prod
   ```
   Or on host: `cd ~/.apps/MEK_LAB_BACKEND && ./db.sh upgrade && ./db.sh seed`.
5. **DNS** — point `api.mek-lab.com` / `salome.mek-lab.com` to prod IPs; set `nginx_certbot_auto: true` in host_vars (see `backend-aws-prod.yml`, `salome-aws-prod.yml`).
6. **HTTPS** — after Certbot, ensure nginx listens on 443: `sudo systemctl reload nginx` if browsers get `ERR_CONNECTION_REFUSED` on `https://`.
7. **Frontend (simulation SPA)** — **S3 + CloudFront** at `mek-lab.com` + `www` (replaces Vercel). Terraform: `enable_frontend_cdn`, `frontend_hostnames = ["mek-lab.com", "www.mek-lab.com"]`. Cloudflare: CNAME `@` and `www` → CloudFront (no IP). Deploy: `./scripts/deploy-frontend production`. API stays `api.mek-lab.com`. See `docs/FRONTEND-AWS-CLOUDFLARE.md`.

### Login / seed (backend)

- API auth uses **`username`**, not `email` (FastAPI body field).
- Default users come from `MEK_LAB_BACKEND/app/db/seed.py` (run via `./db.sh seed` or `playbooks/seed.yml`).
- Typical admin after seed: `admin@mek-lab.com` / password defined in seed script (`MEK_LAB_ADMIN_SEED_PASSWORD` in repo).
- If login works on `curl` but fails in browser: check **HTTPS** (frontend uses `https://api.mek-lab.com`), hard-refresh, and DB connectivity in `journalctl -u backendserver`.

## Security Standard

- Never commit plaintext credentials/tokens.
- Use `zz_secrets.local.yml`, environment variables, or Ansible Vault.
- Keep runtime files in `infra_ansible/.ansible/` (gitignored).
- Rotate any exposed secret immediately.

## Inventory and Host Standards

- Connection details in `host_vars/<host>.yml` when possible.
- Production backend: `nginx_certbot_auto: true` only after DNS points at the host.
- Set `monitoring_enabled: false` on staging if it should not be scraped.

## App env files (not manual copy)

- Backend/GEO/LLM: role `python_app` renders `roles/python_app/templates/env/*.env.j2` → `~/.apps/<REPO>/.env`.
- Salome: `playbooks/site-salome-apps.yml` writes `app/.env` and repo-root `.env` from `salomeserver.env.j2`.
- Do not scp `.env` from staging unless debugging; re-run playbooks so templates match vault.

## Monitoring/Alerting Standards

- Prometheus targets are inventory-driven.
- Alert rules must identify service and target clearly.
- Alertmanager routing must degrade safely when optional integrations are unset.
- Fix false-positive floods in templates, not manual silences.

## Backend host (`MEK_LAB_BACKEND` + GEO + LLM)

- Playbook: `playbooks/site-backend-apps.yml` (after `site-base-agents.yml` in `site.yml`).
- Group vars: `inventories/prod/group_vars/backend.yml`.
- Creates `mateen_fastians`, `~/.apps`, nginx, three systemd units (`backendserver`, `geoserver`, `llmserver`).
- GEO uses conda role (`freecad_env`); if conda tasks fail under Ansible 2.20+, role uses `runuser` with `HOME` set (see `roles/conda/tasks/main.yml`).
- Host var `ansible_remote_tmp: /tmp/ansible-remote-<hostname>` avoids ACL errors with `become_user`.

## Salome API host (`MEK_LAB_SALOME`)

- Playbook: `playbooks/site-salome-apps.yml` (nginx + clone + Singularity runtime + `salomeserver`).
- Group vars: `inventories/prod/group_vars/salome.yml`.
- **`salome_code_aster_bin`**: optional explicit path to host `as_run`; empty = discover under `salome_runtime_dir` / `/opt`.
- **`salome_deploy_code_aster_wrapper`**: when true (default), installs Singularity wrapper for `as_run`.
- **`salome_code_aster_export_version`**: must match overlay subdir (default `testing`).
- **`salome_code_aster_export_overlay`**: stages `share/aster` and bind-mounts onto `<asrun-root>/<export_version>/`.
- **`salome_code_aster_version_dir_in_image`**, **`salome_code_aster_share_aster_path`**: optional SIF paths if discovery fails.
- **`salome_app_home_mode`**: default `0755` so `ubuntu` can reach SIF under `opt/`.

### Code_Aster / SALOME runtime traps

- **Trap 1: `testing/config.txt` not found** — bind-mount staged `share/aster` to `<asrun-root>/<profile>`.
- **Trap 2: `libdmumps.so` missing** — wrapper must export `RUNASTER_ROOT` and extend `LD_LIBRARY_PATH`.
- **Trap 3: `medcoupling` import** — append MEDCoupling to `PYTHONPATH`/`LD_LIBRARY_PATH` in wrapper.
- **Trap 4: permission denied under `opt/`** — keep `salome_app_home_mode: "0755"` or use `sudo -u mateen_fastians`.

### Required Salome smoke tests (after deploy)

Run against `salome-aws-prod` (or staging):

```bash
# 1) API liveness
ansible -i inventories/prod/hosts.ini salome-aws-prod -m shell \
  -a 'curl -sS -o /tmp/health.out -w "%{http_code}\n" http://127.0.0.1:8000/health && cat /tmp/health.out' -b

# 2) Code_Aster minimal run (no MED)
ansible -i inventories/prod/hosts.ini salome-aws-prod -m shell -b --become-user mateen_fastians -a '
d=/tmp/asrun_probe_$$; mkdir -p "$d";
printf "DEBUT();\nFIN();\n" > "$d/t.comm";
cat > "$d/t.export" <<EOF
P actions make_etude
P version testing
P mode interactif
P memory_limit 1024.0
P time_limit 120.0
A memjeveux 64.0
A tpmax 120.0
F comm $d/t.comm D 1
F mess $d/t.mess R 6
EOF
/home/mateen_fastians/opt/salome_meca/code_aster_wrappers/bin/as_run --run "$d/t.export"; rc=$?; echo "RC=$rc"; rm -rf "$d"'

# 3) MED read path (medcoupling)
ansible -i inventories/prod/hosts.ini salome-aws-prod -m shell -b --become-user mateen_fastians -a '
d=/tmp/asrun_med_probe_$$; mkdir -p "$d";
m=$(find /home/mateen_fastians/opt/MEK_LAB_SALOME/resources -name "*.med" | head -1);
cat > "$d/t.comm" <<EOF
DEBUT();
MAIL = LIRE_MAILLAGE(FORMAT="MED", UNITE=20);
FIN();
EOF
cat > "$d/t.export" <<EOF
P actions make_etude
P version testing
P mode interactif
P memory_limit 1024.0
P time_limit 120.0
A memjeveux 64.0
A tpmax 120.0
F comm $d/t.comm D 1
F mmed $m D 20
F mess $d/t.mess R 6
EOF
/home/mateen_fastians/opt/salome_meca/code_aster_wrappers/bin/as_run --run "$d/t.export"; rc=$?; echo "RC=$rc"; rm -rf "$d"'
```

## Common production incidents

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| `net::ERR_CONNECTION_REFUSED` on `https://api...` | Nginx not on 443 / Certbot not applied | `sudo systemctl reload nginx`; verify `ss -tlnp \| grep 443` |
| Login 401 / DB errors in logs | Postgres missing or not seeded | Install Postgres, `./db.sh upgrade`, `./db.sh seed`, restart `backendserver` |
| `502` on `/geo/` or `/llm/` | `geoserver` / `llmserver` down | Check `systemctl status`; finish conda/geo/llm provision |
| `503` on `load-cad` | Backend up but **GEO (8001) down** | `journalctl -u geoserver`; often missing `freecad_env/bin/uvicorn` → `pip install -r ~/.apps/MEK_LAB_GEO/requirements.txt` in conda env, `systemctl restart geoserver` |

**GEO performance env** (in `roles/python_app/templates/env/geoserver.env.j2`, prod `group_vars/geo.yml`):

- `GEO_SKIP_STL_CAPTURE=1` — skip STL capture during load-cad
- `GEO_DISABLE_SUBCOMPONENT_JSON=1` + `GEO_MAX_SUBCOMPONENTS_PER_OBJECT=180` — cap subcomponent JSON on large assemblies
- `geo_saas_backend_url` — internal backend URL for upload-step callbacks (split: `http://10.2.2.140:8000`, not `127.0.0.1`)

**API nginx gzip** — `roles/nginx/templates/gzip.conf.j2` on backend host compresses JSON (and `model/gltf+json`) for `/` and `/geo/` proxied responses.

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Git clone failed on new host | No deploy key for `mateen_fastians` | Copy `.ssh` from staging (see checklist) |

## Change Checklist

- [ ] `ansible-inventory --host <host>` resolves expected vars.
- [ ] `bash ./scripts/sync-env-production.sh` if using env-based secrets.
- [ ] `./scripts/provision <host> --check` when practical.
- [ ] Real run uses `--limit` / `--tags`.
- [ ] Docs updated when behavior changes.
