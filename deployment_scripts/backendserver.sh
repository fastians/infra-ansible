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

sudo systemctl restart "$SERVICE_UNIT"

echo "[DEPLOY] Verifying service at http://127.0.0.1:${PORT}/health..."
for i in {1..10}; do
  curl -sf "http://127.0.0.1:${PORT}/health" && break
  sleep 1
done

echo "[DEPLOY OK] $SERVICE_NAME"
