#!/bin/bash
# Build .env.production from zz_secrets.local.yml (for ./scripts/provision load-env).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="${ROOT}/inventories/prod/group_vars/all/zz_secrets.local.yml"
OUT="${ROOT}/.env.production"

if [[ ! -f "${SECRETS}" ]]; then
  echo "Missing ${SECRETS} — copy from zz_secrets.local.example.yml"
  exit 1
fi

export SECRETS_FILE="${SECRETS}" OUT_FILE="${OUT}"
python3 <<'PY'
import pathlib, re, os

secrets = pathlib.Path(os.environ["SECRETS_FILE"])
out = pathlib.Path(os.environ["OUT_FILE"])

mapping = {
    "vault_mek_lab_backend_repo_url": "VAULT_MEK_LAB_BACKEND_REPO_URL",
    "vault_geoserver_repo_url": "VAULT_GEOSERVER_REPO_URL",
    "vault_meklab_llm_repo_url": "VAULT_MEKLAB_LLM_REPO_URL",
    "vault_salome_repo_url": "VAULT_SALOME_REPO_URL",
    "vault_salome_engineering_repo_url": "VAULT_SALOME_ENGINEERING_REPO_URL",
    "vault_geoserver_engineering_repo_url": "VAULT_GEOSERVER_ENGINEERING_REPO_URL",
    "vault_backend_postgres_admin_password": "VAULT_BACKEND_POSTGRES_ADMIN_PASSWORD",
    "vault_backend_bootstrap_admin_password": "VAULT_BACKEND_BOOTSTRAP_ADMIN_PASSWORD",
    "vault_backend_database_url": "VAULT_BACKEND_DATABASE_URL",
    "vault_backend_secret_key": "VAULT_BACKEND_SECRET_KEY",
    "vault_internal_api_key": "VAULT_INTERNAL_API_KEY",
    "vault_sendgrid_api_key": "VAULT_SENDGRID_API_KEY",
    "vault_sendgrid_from_email": "VAULT_SENDGRID_FROM_EMAIL",
    "vault_aws_access_key_id": "VAULT_AWS_ACCESS_KEY_ID",
    "vault_aws_secret_access_key": "VAULT_AWS_SECRET_ACCESS_KEY",
    "vault_aws_ses_region": "VAULT_AWS_SES_REGION",
    "vault_aws_ses_from_email": "VAULT_AWS_SES_FROM_EMAIL",
    "vault_aws_ses_sender_name": "VAULT_AWS_SES_SENDER_NAME",
    "vault_postmark_api_key": "VAULT_POSTMARK_API_KEY",
    "vault_toss_secret_key": "VAULT_TOSS_SECRET_KEY",
    "vault_llm_database_url": "VAULT_LLM_DATABASE_URL",
    "vault_mem0_api_key": "VAULT_MEM0_API_KEY",
    "vault_openrouter_api_key": "VAULT_OPENROUTER_API_KEY",
    "vault_pinecone_api_key": "VAULT_PINECONE_API_KEY",
}

text = secrets.read_text()
lines = ["# Auto-generated from zz_secrets.local.yml — gitignored", ""]
count = 0
for key, env_key in mapping.items():
    m = re.search(rf"^{re.escape(key)}:\s*(.+)$", text, re.M)
    if not m:
        continue
    raw = m.group(1).strip()
    if raw.startswith('"') and raw.endswith('"'):
        val = raw[1:-1].replace('\\"', '"')
    elif raw.startswith("'") and raw.endswith("'"):
        val = raw[1:-1]
    else:
        val = raw
    if val in ("", "CHANGE_ME"):
        continue
    val = val.replace("\\", "\\\\").replace('"', '\\"')
    lines.append(f'{env_key}="{val}"')
    count += 1

out.write_text("\n".join(lines) + "\n")
print(f"Wrote {out} ({count} variables)")
PY
