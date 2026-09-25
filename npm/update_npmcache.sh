#!/usr/bin/env bash
# update_npmcache.sh
# 現在の npm グローバルパッケージ状態を npmfile.cache に記録する
#
# 動作:
#   npm list -g --depth=0 の結果をパッケージ名のみ（バージョンなし）で
#   npmfile.cache に書き出す。npm 本体は除外する。
#   --print を付けるとキャッシュを書かず、同じ内容を標準出力へ出す（--dry-run 用）。
#
# 使い方:
#   bash npm/update_npmcache.sh [--print]
#   dots npm cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE_CACHE="$DOTFILES_DIR/npm/npmfile.cache"

PRINT_ONLY=0
case "${1:-}" in
  "") ;;
  --print) PRINT_ONLY=1 ;;
  *) echo "usage: update_npmcache.sh [--print]" >&2; exit 2 ;;
esac

_list_packages() {
  npm list -g --depth=0 --json 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name in sorted(data.get('dependencies', {})):
    if name != 'npm':
        print(name)
"
}

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  _list_packages
else
  _list_packages > "$NPMFILE_CACHE"
  echo "npmfile.cache updated."
fi
