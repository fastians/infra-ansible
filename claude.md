# CLAUDE.md - Infra Ansible Engineering Standard

This document is the operating contract for `infra_ansible`.

## Goals

- Keep provisioning deterministic and repeatable.
- Minimize production risk during updates.
- Keep host targeting explicit and auditable.
- Keep secrets out of git-tracked plaintext files.

## Source of Truth

- Inventory: `inventories/prod/hosts.ini`
- Host-specific overrides: `inventories/prod/host_vars/*.yml`
- Shared environment config: `inventories/prod/group_vars/**/*.yml`
- Main orchestration: `site.yml`
- Day-2 wrapper: `./scripts/provision`

## Required Runtime Pattern

- Always run via `./scripts/provision` (or `make`) for routine operations.
- Use `--limit <host>` when targeting a single server.
- Use `--tags` for narrow changes.
- Prefer idempotent re-runs over one-off manual server edits.
- Keep two env profiles in repo root (gitignored): `.env.local` and `.env.production`.
- Default script profile is production; use `APP_ENV=local` only for local/dev runs.

Examples:

```bash
./scripts/provision monitoring-server
./scripts/provision backend-server --tags nginx
./scripts/provision verify
```

## Security Standard

- Never commit plaintext credentials/tokens.
- Use environment variables or Ansible Vault for secret values.
- Keep runtime files in `infra_ansible/.ansible/` (gitignored).
- If a secret is exposed, rotate it immediately.

## Inventory and Host Standards

- Keep host connection details in `host_vars/<host>.yml` when possible.
- Use simple host names in `hosts.ini`; avoid long inline connection strings.
- If a host should not be scraped by monitoring, set:

```yaml
monitoring_enabled: false
```

## Monitoring/Alerting Standards

- Prometheus target generation must be inventory-driven.
- Alert rules should identify service and target clearly.
- Alertmanager routing should degrade safely when optional integrations are unset.
- Any false-positive flood should be fixed in config/templates, not muted manually.

## Salome API host (`MEK_LAB_SALOME`)

- Playbook: `playbooks/site-salome-apps.yml` (nginx + clone + Singularity runtime + `salomeserver`).
- Group vars: `inventories/prod/group_vars/salome.yml`.
- **`salome_code_aster_bin`**: optional explicit path to the directory containing host `as_run`; empty lets the playbook discover under `salome_runtime_dir` / `/opt` (wrapper lives under `…/code_aster_wrappers/bin/as_run`).
- **`salome_deploy_code_aster_wrapper`**: when true (default), installs the Singularity wrapper so `as_run` runs inside the SIF.
- **`salome_code_aster_export_version`**: passed to `app/.env` as `CODE_ASTER_EXPORT_VERSION`; must match the overlay subdir name (default `testing`).
- **`salome_code_aster_export_overlay`**: host directory where the playbook stages the full Code_Aster `share/aster` tree for the chosen profile, then bind-mounts it onto `<asrun-root>/<export_version>/`. Needed because `as_run` resolves `P version testing` to `/opt/public/.../asrun-*/testing/config.txt` while SALOME-MECA stores real files under `/opt/salome_meca/.../Code_aster_testing-*/share/aster/`.
- **`salome_code_aster_version_dir_in_image`**: optional explicit asrun root *inside the SIF* (under `/opt/public/.../asrun-*`). Empty = discover.
- **`salome_code_aster_share_aster_path`**: optional explicit `.../share/aster` path *inside the SIF* if glob discovery fails.
- **`salome_app_home_mode`**: mode for `/home/mateen_fastians` (default `0755` so any local user e.g. `ubuntu` can traverse to `opt/` and run `singularity exec` on the SIF; app `.env` files remain `0600`). Set `0750` in host_vars if you want a locked-down home and use `sudo -u mateen_fastians` for debugging.
- Deploy example: `ansible-playbook -i inventories/prod/hosts.ini playbooks/site-salome-apps.yml --limit salome-aws-prod -v`

### Lessons Learned (Code_Aster/SALOME runtime traps)

- **Trap 1: `testing/config.txt` not found**: `as_run` looks under `/opt/public/.../asrun-*/<profile>/config.txt`, but SALOME-MECA keeps real profile files under `/opt/salome_meca/.../Code_aster_*/share/aster`.  
  **Fix**: stage `share/aster` to `salome_code_aster_export_overlay/<profile>` and bind-mount to `<asrun-root>/<profile>`.
- **Trap 2: `libdmumps.so` missing**: profile/environment not fully loaded for non-interactive `singularity exec`.  
  **Fix**: wrapper exports `RUNASTER_ROOT`, sources profile, and extends `LD_LIBRARY_PATH`.
- **Trap 3: `ModuleNotFoundError: medcoupling` during `LIRE_MAILLAGE`**: MEDCoupling Python site-packages are absent from default `PYTHONPATH`.  
  **Fix**: wrapper appends MEDCOUPLING site-packages and libs to `PYTHONPATH`/`LD_LIBRARY_PATH`.
- **Trap 4: host user cannot access SIF path** (`permission denied` under `/home/mateen_fastians/opt`).  
  **Fix**: keep `salome_app_home_mode: "0755"` for operational access, or use `sudo -u mateen_fastians`.

### Required Salome Smoke Tests (after deploy)

Run these from control host via Ansible against `salome-aws-prod`:

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

# 3) MED read path (covers medcoupling)
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

## Salome API host (`MEK_LAB_SALOME`)

- Playbook: `playbooks/site-salome-apps.yml` (nginx + clone + Singularity runtime + `salomeserver`).
- Group vars: `inventories/prod/group_vars/salome.yml`.
- **`salome_code_aster_bin`**: optional explicit path to the directory containing host `as_run`; empty lets the playbook discover under `salome_runtime_dir` / `/opt` (wrapper lives under `…/code_aster_wrappers/bin/as_run`).
- **`salome_deploy_code_aster_wrapper`**: when true (default), installs the Singularity wrapper so `as_run` runs inside the SIF.
- **`salome_code_aster_export_version`**: passed to `app/.env` as `CODE_ASTER_EXPORT_VERSION` (default `testing`; LGPL images often lack the `stable` Code_Aster profile).
- Deploy example: `ansible-playbook -i inventories/prod/hosts.ini playbooks/site-salome-apps.yml --limit salome-aws-prod -v`

## Change Checklist

- [ ] `ansible-inventory --host <host>` resolves expected vars.
- [ ] `./scripts/provision <host> --check` passes for touched area when practical.
- [ ] Real run uses minimal scope (`--limit` / `--tags`).
- [ ] Docs/README updated when behavior changes.
