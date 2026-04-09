#!/usr/bin/env bash
# update_pipxcache.sh
# 現在の pipx パッケージ状態を pipxfile.cache に記録する
#
# 動作:
#   pipx list --json の結果をパッケージ名のみ（バージョンなし）で
#   pipxfile.cache に書き出す。
#
# 使い方:
#   bash pipx/update_pipxcache.sh
#   make pipx-cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"

pipx list --json 2>/dev/null \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name in sorted(data.get('venvs', {})):
    print(name)
" > "$PIPXFILE_CACHE"

echo "pipxfile.cache updated."
