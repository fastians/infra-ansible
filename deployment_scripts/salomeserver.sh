#!/bin/bash
set -e

SERVICE_NAME="salomeserver"
APP_DIR="/home/mateen_fastians/opt/MEK_LAB_SALOME"
SERVICE_UNIT="salomeserver.service"
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

# Use venv pip explicitly (avoids PEP 668 externally-managed-environment)
timeout 300 .venv/bin/pip install -r app/requirements.txt --no-input --quiet

echo "[DEPLOY] Systemd restart + health check: Ansible (root)."

echo "[DEPLOY OK] $SERVICE_NAME"
