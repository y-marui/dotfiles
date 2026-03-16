#!/usr/bin/env bash
# update_dockcache.sh
# 現在の Dock・サイドバー状態を dockfile.cache に記録する
#
# 動作:
#   dockutil / mysides で現在の状態を取得し dockfile.cache に書き出す
#
# 使い方:
#   bash macos/update_dockcache.sh
#   make dock-cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
SNAPSHOT="${PRIVATE_DIR}/macos/dockfile.cache"

_current_dock() {
  dockutil --list 2>/dev/null | awk -F'\t' '{
    path = $2
    gsub("^file://", "", path)
    gsub(/%20/, " ", path)
    sub("/$", "", path)
    print path
  }'
}
_current_sidebar() {
  mysides list 2>/dev/null | awk -F' -> ' '{print "sidebar\t" $1 "\t" $2}'
}
_capture() {
  _current_dock | awk '{print "dock\t" $0}'
  _current_sidebar
}

_capture > "$SNAPSHOT"
echo "dockfile.cache updated."
