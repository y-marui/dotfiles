#!/usr/bin/env bash
# prune_pipxfile.sh
# pipxfile にない pipx パッケージを pipx uninstall で削除する
#
# 動作:
#   1. 現在のパッケージ一覧と pipxfile を比較する
#   2. 削除対象を表示する。--dry-run の場合はここで終了する（何も変更しない）
#   3. 削除前に一覧を <backup-dir>/pipx-removed.txt へ保存してから削除する
#   4. pipxfile.cache を更新する
#
# 使い方:
#   bash pipx/prune_pipxfile.sh [--dry-run] [--backup-dir DIR]
#   dots pipx prune
#
# --backup-dir の既定は ~/.dotfiles-backup/<timestamp>。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
DRY_RUN=0
BACKUP_DIR=""

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --backup-dir)
      (( $# >= 2 )) || { echo "error: --backup-dir requires a directory" >&2; exit 2; }
      BACKUP_DIR="$2"
      shift 2
      ;;
    *) echo "usage: prune_pipxfile.sh [--dry-run] [--backup-dir DIR]" >&2; exit 2 ;;
  esac
done

load_names() {
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1" | sort
}

installed=$(bash "$DOTFILES_DIR/pipx/update_pipxcache.sh" --print | sort)
to_remove=$(comm -23 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$PIPXFILE"))

echo "==> Checking for packages not in pipxfile..."
if [[ -z "$to_remove" ]]; then
  echo "  (no unmanaged packages)"
  exit 0
fi

while IFS= read -r pkg; do
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] uninstall  $pkg"
  else
    echo "  uninstall  $pkg"
  fi
done <<< "$to_remove"

[[ "$DRY_RUN" -eq 0 ]] || exit 0

BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup/$(date +%Y%m%d%H%M%S)}"
mkdir -p "$BACKUP_DIR"
printf '%s\n' "$to_remove" > "$BACKUP_DIR/pipx-removed.txt"
echo "  BACKUP  $BACKUP_DIR/pipx-removed.txt"

while IFS= read -r pkg; do
  pipx uninstall "$pkg"
done <<< "$to_remove"

bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"
