#!/usr/bin/env bash
set -euo pipefail

# --all: ghq-update の依存更新対象を keep-up-to-date=true から
# .venv/node_modules があるリポジトリまで拡張する（ghq-update --all 相当）。
ghq_update_all=false
if [[ "${1:-}" == "--all" ]]; then
  ghq_update_all=true
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "error: unknown argument: $1" >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_env="${HOMEBRIDGE_COMPOSE_ENV:-/etc/homebridge/compose.env}"
container_mode=false
if sudo test -f "$compose_env"; then
  container_mode=true
  sudo docker compose --env-file "$compose_env" -f "$repo_dir/rpi/homebridge/compose.yaml" config --quiet
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

# システム更新
sudo apt update
sudo apt -y upgrade
sudo apt dist-upgrade -y
sudo apt autoremove -y
sudo apt autoclean

# Prezto と、その配下で管理される Powerlevel10k を更新
bash "$(dirname "${BASH_SOURCE[0]}")/update-prezto.sh"

if $container_mode; then
  # Image digest is selected explicitly in the private env file before updating.
  # Core/UI/Node come from the image; plugins remain in the persistent data.
  sudo docker compose --env-file "$compose_env" -f "$repo_dir/rpi/homebridge/compose.yaml" pull
  sudo docker compose --env-file "$compose_env" -f "$repo_dir/rpi/homebridge/compose.yaml" up -d
else
  echo "  SKIP    Homebridge (no configured container)"
fi

# ghq 管理リポジトリの更新
if command -v ghq-update >/dev/null 2>&1; then
  if [[ "${ghq_update_all}" == true ]]; then
    ghq-update --pull-all --all
  else
    ghq-update --pull-all
  fi
else
  echo "  SKIP    ghq-update (command not found)"
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
