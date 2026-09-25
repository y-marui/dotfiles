#!/usr/bin/env bash
# prune_npmfile.sh
# npmfile にないグローバルパッケージを npm uninstall -g で削除する
#
# 動作:
#   1. 現在のパッケージ一覧と npmfile を比較する（npm 本体は一覧に含まれない）
#   2. 削除対象を表示する。--dry-run の場合はここで終了する（何も変更しない）
#   3. 削除前に一覧を <backup-dir>/npm-removed.txt へ保存してから削除する
#   4. npmfile.cache を更新する
#
# 使い方:
#   bash npm/prune_npmfile.sh [--dry-run] [--backup-dir DIR]
#   dots npm prune
#
# --backup-dir の既定は ~/.dotfiles-backup/<timestamp>。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE="$DOTFILES_DIR/npm/npmfile"
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
    *) echo "usage: prune_npmfile.sh [--dry-run] [--backup-dir DIR]" >&2; exit 2 ;;
  esac
done

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

installed=$(bash "$DOTFILES_DIR/npm/update_npmcache.sh" --print | sort)
to_remove=$(comm -23 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$NPMFILE"))

echo "==> Checking for packages not in npmfile..."
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
printf '%s\n' "$to_remove" > "$BACKUP_DIR/npm-removed.txt"
echo "  BACKUP  $BACKUP_DIR/npm-removed.txt"

while IFS= read -r pkg; do
  npm uninstall -g "$pkg"
done <<< "$to_remove"

bash "$DOTFILES_DIR/npm/update_npmcache.sh"
