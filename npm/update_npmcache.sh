#!/usr/bin/env bash
# update_npmcache.sh
# 現在の npm グローバルパッケージ状態を npmfile.cache に記録する
#
# 動作:
#   npm list -g --depth=0 の結果をパッケージ名のみ（バージョンなし）で
#   npmfile.cache に書き出す。npm 本体は除外する。
#
# 使い方:
#   bash npm/update_npmcache.sh
#   make npm-cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE_CACHE="$DOTFILES_DIR/npm/npmfile.cache"

npm list -g --depth=0 --json 2>/dev/null \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name in sorted(data.get('dependencies', {})):
    if name != 'npm':
        print(name)
" > "$NPMFILE_CACHE"

echo "npmfile.cache updated."
