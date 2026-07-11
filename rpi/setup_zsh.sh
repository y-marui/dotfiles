#!/usr/bin/env bash
# setup_zsh.sh
# デフォルトシェルを zsh に変更する（すでに zsh の場合はスキップ）
#
# 使い方:
#   bash rpi/setup_zsh.sh

set -euo pipefail

zsh_path="$(command -v zsh)"
current_shell="$(getent passwd "$USER" | cut -d: -f7)"

if [[ "$current_shell" == "$zsh_path" ]]; then
  echo "  SKIP    zsh (すでにデフォルトシェルです)"
  exit 0
fi

sudo chsh -s "$zsh_path" "$USER"
echo "  SHELL   デフォルトシェルを $zsh_path に変更しました（再ログインで反映されます）"
