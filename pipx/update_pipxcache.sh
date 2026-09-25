#!/usr/bin/env bash
# update_pipxcache.sh
# 現在の pipx パッケージ状態を pipxfile.cache に記録する
#
# 動作:
#   pipx list --json の結果をパッケージ名のみ（バージョンなし）で
#   pipxfile.cache に書き出す。
#   --print を付けるとキャッシュを書かず、同じ内容を標準出力へ出す（--dry-run 用）。
#
# 使い方:
#   bash pipx/update_pipxcache.sh [--print]
#   dots pipx cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"

PRINT_ONLY=0
case "${1:-}" in
  "") ;;
  --print) PRINT_ONLY=1 ;;
  *) echo "usage: update_pipxcache.sh [--print]" >&2; exit 2 ;;
esac

_list_packages() {
  pipx list --json 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name in sorted(data.get('venvs', {})):
    print(name)
"
}

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  _list_packages
else
  _list_packages > "$PIPXFILE_CACHE"
  echo "pipxfile.cache updated."
fi
