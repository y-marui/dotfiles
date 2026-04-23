#!/usr/bin/env bash
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

# システム更新
sudo apt update
sudo apt -y upgrade
sudo apt dist-upgrade -y
sudo apt autoremove -y
sudo apt autoclean

# Node.js の更新
sudo hb-service update-node

# Homebridge 本体の更新
sudo env TMPDIR=/var/tmp PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/npm install -g homebridge@latest

# インストール済みプラグインの更新
sudo env TMPDIR=/var/tmp PATH="/opt/homebridge/bin:$PATH" /opt/homebridge/bin/npm update -g

# Homebridge 再起動
sudo systemctl restart homebridge

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
