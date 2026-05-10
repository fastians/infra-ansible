#!/bin/bash
set -e

SERVICE_NAME="backendserver"
APP_DIR="/home/mateen_fastians/.apps/MEK_LAB_BACKEND"
SERVICE_UNIT="backendserver.service"
PORT="8000"
BRANCH="${1:-main}"

echo "[DEPLOY] $SERVICE_NAME ($BRANCH)"

cd "$APP_DIR"
git fetch origin
git checkout "$BRANCH"
git pull

if [ ! -d ".venv" ]; then
    echo "[SETUP] Creating virtual environment..."
    python3 -m venv .venv
fi

# Use venv pip explicitly (avoids PEP 668 externally-managed-environment); requirements in repo root
timeout 300 .venv/bin/pip install -r requirements.txt --no-input --quiet

echo "[DEPLOY] Running database migrations..."
.venv/bin/alembic upgrade head

echo "[DEPLOY] Current commit: $(git rev-parse HEAD)"
echo "[DEPLOY] Commit message: $(git log -1 --pretty=%B)"

# systemd restart runs as root in playbooks/deploy.yml (deploy user often has no passwordless sudo).
echo "[DEPLOY] Systemd restart + health check: Ansible (root)."

echo "[DEPLOY OK] $SERVICE_NAME"
