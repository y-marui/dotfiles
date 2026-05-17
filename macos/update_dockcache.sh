#!/usr/bin/env bash
# update_dockcache.sh
# 現在の Dock・サイドバー状態を dockfile.cache に記録する
#
# 動作:
#   dockutil / mysides.py で現在の状態を取得し dockfile.cache に書き出す
#
# 使い方:
#   bash macos/update_dockcache.sh
#   make dock-cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
SNAPSHOT="${PRIVATE_DIR}/macos/dockfile.cache"
YELLOW='\033[1;33m'
RESET='\033[0m'

_mysides() {
  if command -v mysides &>/dev/null; then
    mysides "$@"
  elif command -v uv &>/dev/null; then
    uv run --with pyobjc python3 "$DOTFILES_DIR/macos/mysides.py" "$@"
  else
    printf '%sError: sidebar tool unavailable — install uv: brew install uv%s\n' "$YELLOW" "$RESET" >&2
    return 1
  fi
}

_current_dock() {
  local output
  if output=$(dockutil --list 2>/dev/null); then
    awk -F'\t' '{
      path = $2
      gsub("^file://", "", path)
      gsub(/%20/, " ", path)
      sub("/$", "", path)
      print path
    }' <<< "$output"
  else
    printf '%sWarning: dockutil failed to run. Dock entries omitted from cache.%s\n' "$YELLOW" "$RESET" >&2
  fi
}
_current_sidebar() {
  local output
  if output=$(_mysides list 2>/dev/null); then
    awk -F' -> ' '{print "sidebar\t" $1 "\t" $2}' <<< "$output"
  else
    printf '%sWarning: sidebar tool not available. Sidebar entries omitted from cache.%s\n' "$YELLOW" "$RESET" >&2
  fi
}
_capture() {
  _current_dock | awk '{print "dock\t" $0}'
  _current_sidebar
}

_capture > "$SNAPSHOT"
echo "dockfile.cache updated."
