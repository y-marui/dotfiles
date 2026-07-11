#!/usr/bin/env bash
# setup_claude-code.sh
# Claude Code の APT リポジトリを登録し、claude-code パッケージをインストールする
#
# 使い方:
#   bash rpi/repos/setup_claude-code.sh

set -euo pipefail

if command -v claude &>/dev/null; then
  echo "  SKIP    claude-code (インストール済み)"
  exit 0
fi

sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
  -o /etc/apt/keyrings/claude-code.asc
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
  | sudo tee /etc/apt/sources.list.d/claude-code.list > /dev/null

sudo apt-get update
sudo apt-get install -y claude-code

echo "  INSTALL claude-code"
