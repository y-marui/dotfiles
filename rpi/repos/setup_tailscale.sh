#!/usr/bin/env bash
# setup_tailscale.sh
# Tailscale の APT リポジトリを登録し、tailscale パッケージをインストールする
# （認証は対話操作が必要なため、インストール後に手動で `sudo tailscale up` すること）
#
# 使い方:
#   bash rpi/repos/setup_tailscale.sh

set -euo pipefail

if command -v tailscale &>/dev/null; then
  echo "  SKIP    tailscale (インストール済み)"
  exit 0
fi

curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null

sudo apt-get update
sudo apt-get install -y tailscale

echo "  INSTALL tailscale"
echo "  NOTE    認証のため 'sudo tailscale up' を手動で実行してください。"
