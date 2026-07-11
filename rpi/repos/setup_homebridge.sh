#!/usr/bin/env bash
# setup_homebridge.sh
# Homebridge の APT リポジトリを登録し、homebridge パッケージをインストールする
# （インストール時に systemd サービスも自動で有効化される）
#
# 使い方:
#   bash rpi/repos/setup_homebridge.sh

set -euo pipefail

if command -v hb-service &>/dev/null; then
  echo "  SKIP    homebridge (インストール済み)"
  exit 0
fi

curl -sfL https://repo.homebridge.io/KEY.gpg | sudo gpg --dearmor -o /usr/share/keyrings/homebridge.gpg
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io stable main" \
  | sudo tee /etc/apt/sources.list.d/homebridge.list > /dev/null

sudo apt-get update
sudo apt-get install -y homebridge

echo "  INSTALL homebridge"
