#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_env="${HOMEBRIDGE_COMPOSE_ENV:-/etc/homebridge/compose.env}"
container_mode=false
native_mode=false
if sudo test -f "$compose_env"; then
  container_mode=true
  sudo docker compose --env-file "$compose_env" -f "$repo_dir/rpi/homebridge/compose.yaml" config --quiet
elif systemctl is-enabled --quiet homebridge.service 2>/dev/null && [[ -x /opt/homebridge/bin/hb-service ]]; then
  native_mode=true
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
elif $native_mode; then
  # Native Homebridge only.
  sudo env PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/hb-service update-node
  sudo env TMPDIR=/var/tmp PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/npm install -g homebridge@latest
  sudo env TMPDIR=/var/tmp PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/npm update -g
else
  echo "  SKIP    Homebridge (no configured container or enabled native service)"
fi

# ghq 管理リポジトリの更新
if command -v ghq-update >/dev/null 2>&1; then
  ghq-update --pull-all
else
  echo "  SKIP    ghq-update (command not found)"
fi

# Homebridge 再起動
if $native_mode; then
  sudo systemctl restart homebridge
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
