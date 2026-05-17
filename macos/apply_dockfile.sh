#!/usr/bin/env bash
# apply_dockfile.sh
# dockfile の内容を Dock・Finder サイドバーに適用する
#
# 動作:
#   1. dotfiles-private/macos/dockfile を読み込む
#   2. Dock・Finder サイドバーをリセットして再構築
#   3. dockfile.cache を更新
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash macos/apply_dockfile.sh
#   make dock

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_FILE="$PRIVATE_DIR/macos/dockfile"
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
  _mysides list > "$BACKUP_DIR/dock-sidebar.txt" 2>&1 || \
    printf '%sWarning: sidebar backup failed — continuing without sidebar backup%s\n' "$YELLOW" "$RESET" >&2
  echo "  BACKUP  $BACKUP_DIR/dock-apps.txt"

  if ! dockutil --no-restart --remove all; then
    printf '%sError: dockutil --remove all failed. Aborting to prevent inconsistent Dock state.%s\n' "$YELLOW" "$RESET" >&2
    exit 1
  fi
else
  printf '%sWarning: dockutil not found. Run: brew install dockutil%s\n' "$YELLOW" "$RESET" >&2
fi

# ── Finder サイドバーをリセット ───────────────────────────────────────────────
if mysides_items=$(_mysides list 2>/dev/null); then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    _mysides remove "$name" 2>/dev/null || \
      printf '%sWarning: sidebar: failed to remove: %s%s\n' "$YELLOW" "$name" "$RESET" >&2
  done < <(awk -F' -> ' '{print $1}' <<< "$mysides_items")
else
  printf '%sWarning: sidebar tool not available. Skipping sidebar reset.%s\n' "$YELLOW" "$RESET" >&2
fi

# ── dock ファイルを1行ずつ適用 ────────────────────────────────────────────────
while IFS=$'\t' read -r type arg1 arg2; do
  case "$type" in
    dock)
      if [[ -e "$arg1" ]]; then
        if [[ -d "$arg1" && "$arg1" != *.app ]]; then
          dockutil --no-restart --add "$arg1" --display stack \
            || printf '%sWarning: dockutil add failed: %s%s\n' "$YELLOW" "$arg1" "$RESET" >&2
        else
          dockutil --no-restart --add "$arg1" \
            || printf '%sWarning: dockutil add failed: %s%s\n' "$YELLOW" "$arg1" "$RESET" >&2
        fi
      else
        printf '%sWarning: skipping (not found): %s%s\n' "$YELLOW" "$arg1" "$RESET" >&2
      fi
      ;;
    sidebar)
      if ! path=$(python3 -c "
import sys
from urllib.parse import unquote
print(unquote(sys.argv[1]).removeprefix('file://').rstrip('/'))
" "$arg2" 2>/dev/null); then
        printf '%sWarning: skipping sidebar entry (python3 failed to decode URL): %s%s\n' "$YELLOW" "$arg2" "$RESET" >&2
        continue
      fi
      if [[ -e "$path" ]]; then
        _mysides add "$arg1" "$arg2" || \
          printf '%sWarning: sidebar: failed to add: %s%s\n' "$YELLOW" "$arg1" "$RESET" >&2
      else
        printf '%sWarning: skipping (not found): %s (%s)%s\n' "$YELLOW" "$arg1" "$path" "$RESET" >&2
      fi
      ;;
  esac
done < "$DOCK_FILE"

killall Dock 2>/dev/null || true

# ── cache を更新 ──────────────────────────────────────────────────────────────
export DOTFILES_DIR
bash "$DOTFILES_DIR/macos/update_dockcache.sh"
echo "Done. dockfile.cache saved to $PRIVATE_DIR/macos/dockfile.cache"
