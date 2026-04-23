#!/bin/bash

# Load environment profile for infra operations.
# Priority:
# 1) APP_ENV
# 2) ENV
# Defaults to: production

load_env_profile() {
  local root_dir="$1"
  local env_name="${APP_ENV:-${ENV:-production}}"
  local env_file="${root_dir}/.env.${env_name}"

  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
    echo "🔐 Loaded environment profile: .env.${env_name}"
    return 0
  fi

  echo "❌ Missing environment profile: ${env_file}"
  echo "Create it from ${root_dir}/.env.${env_name}.example"
  return 1
}
