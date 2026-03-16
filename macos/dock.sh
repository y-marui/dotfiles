#!/usr/bin/env bash
# dock.sh
# dock ファイルの内容を Dock・Finder サイドバーに適用する
#
# 動作:
#   1. dotfiles-private/macos/dockfile を読み込む
#   2. Dock・Finder サイドバーをリセットして再構築
#   3. dock.cache を更新
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash macos/dock.sh
#   make dock

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_FILE="$PRIVATE_DIR/macos/dockfile"
YELLOW='\033[1;33m'
RESET='\033[0m'

# ── dock ファイルのチェック ────────────────────────────────────────────────────
if [[ ! -f "$DOCK_FILE" ]]; then
  printf '%sError: dock file not found: %s%s\n' "$YELLOW" "$DOCK_FILE" "$RESET" >&2
  echo "  Run 'make dock-sync' to create dockfile from current dock state." >&2
  exit 1
fi
if [[ ! -s "$DOCK_FILE" ]]; then
  printf '%sError: dock file is empty: %s%s\n' "$YELLOW" "$DOCK_FILE" "$RESET" >&2
  echo "  Run 'make dock-sync' to populate it from current dock state." >&2
  exit 1
fi

# ── Dock を適用 ───────────────────────────────────────────────────────────────
if command -v dockutil &>/dev/null; then
  BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  dockutil --list 2>/dev/null > "$BACKUP_DIR/dock-apps.txt" || true
  mysides list 2>/dev/null > "$BACKUP_DIR/dock-sidebar.txt" || true
  echo "  BACKUP  $BACKUP_DIR/dock-apps.txt"

  dockutil --no-restart --remove all
else
  printf '%sWarning: dockutil not found. Run: brew install dockutil%s\n' "$YELLOW" "$RESET" >&2
fi

# ── Finder サイドバーをリセット ───────────────────────────────────────────────
if command -v mysides &>/dev/null; then
  mysides list | awk '{print $1}' | while IFS= read -r name; do
    [ -n "$name" ] && mysides remove "$name" 2>/dev/null || true
  done
else
  printf '%sWarning: mysides not found. Run: brew install mysides%s\n' "$YELLOW" "$RESET" >&2
fi

# ── dock ファイルを1行ずつ適用 ────────────────────────────────────────────────
while IFS=$'\t' read -r type arg1 arg2; do
  case "$type" in
    dock)
      if [[ -e "$arg1" ]]; then
        dockutil --no-restart --add "$arg1"
      else
        printf '%sWarning: skipping (not found): %s%s\n' "$YELLOW" "$arg1" "$RESET" >&2
      fi
      ;;
    sidebar)
      path=$(python3 -c "
import sys
from urllib.parse import unquote
print(unquote(sys.argv[1]).removeprefix('file://').rstrip('/'))
" "$arg2")
      if [[ -e "$path" ]]; then
        mysides add "$arg1" "$arg2"
      else
        printf '%sWarning: skipping (not found): %s (%s)%s\n' "$YELLOW" "$arg1" "$path" "$RESET" >&2
      fi
      ;;
  esac
done < "$DOCK_FILE"

killall Dock 2>/dev/null || true

# ── cache を更新 ──────────────────────────────────────────────────────────────
export DOTFILES_DIR
bash "$DOTFILES_DIR/macos/dock-sync.sh" --snapshot-only
echo "Done. dockfile.cache saved to $PRIVATE_DIR/macos/dockfile.cache"
