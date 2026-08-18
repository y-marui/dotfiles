#!/usr/bin/env bash
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

# システム更新
sudo apt update
sudo apt -y upgrade
sudo apt dist-upgrade -y
sudo apt autoremove -y
sudo apt autoclean

# Prezto と、その配下で管理される Powerlevel10k を更新
bash "$(dirname "${BASH_SOURCE[0]}")/update-prezto.sh"

# Node.js の更新
sudo hb-service update-node

# Homebridge 本体の更新
sudo env TMPDIR=/var/tmp PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/npm install -g homebridge@latest

# インストール済みプラグインの更新
sudo env TMPDIR=/var/tmp PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/npm update -g

# ghq 管理リポジトリの更新
if command -v ghq-update >/dev/null 2>&1; then
  ghq-update --pull-all
else
  echo "  SKIP    ghq-update (command not found)"
fi

# Homebridge 再起動
sudo systemctl restart homebridge

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
