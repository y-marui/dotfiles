#!/usr/bin/env bash
# apply_npmfile.sh
# npmfile の内容をローカルの npm グローバル環境に適用する
#
# 動作:
#   1. npmfile にあって未インストールのものをインストール
#   2. 続けて prune_npmfile.sh で npmfile にないものを削除（--no-prune で省略）
#      --no-prune の場合は未管理パッケージを一覧表示するだけで削除しない
#   3. npmfile.cache を更新
#   --dry-run は何も変更せず、実行した場合の変更予定だけを表示する。
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash npm/apply_npmfile.sh [--no-prune] [--dry-run] [--backup-dir DIR]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE="$DOTFILES_DIR/npm/npmfile"
NO_PRUNE=0
DRY_RUN=0
BACKUP_ARGS=()

while (( $# > 0 )); do
  case "$1" in
    --no-prune) NO_PRUNE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --backup-dir)
      (( $# >= 2 )) || { echo "error: --backup-dir requires a directory" >&2; exit 2; }
      BACKUP_ARGS=(--backup-dir "$2")
      shift 2
      ;;
    *) echo "usage: apply_npmfile.sh [--no-prune] [--dry-run] [--backup-dir DIR]" >&2; exit 2 ;;
  esac
done

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

installed=$(bash "$DOTFILES_DIR/npm/update_npmcache.sh" --print | sort)
to_install=$(comm -13 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$NPMFILE"))
to_remove=$(comm -23 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$NPMFILE"))

# ── インストール ───────────────────────────────────────────────────────────────
echo "==> Installing packages from npmfile..."
if [[ -z "$to_install" ]]; then
  echo "  (already up to date)"
else
  while IFS= read -r pkg; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  [dry-run] install  $pkg"
    else
      echo "  install  $pkg"
      npm install -g "$pkg"
    fi
  done <<< "$to_install"
fi

# ── 不要パッケージの削除 ───────────────────────────────────────────────────────
echo ""
if [[ "$NO_PRUNE" -eq 0 ]]; then
  prune_args=()
  [[ "$DRY_RUN" -eq 0 ]] || prune_args+=(--dry-run)
  bash "$DOTFILES_DIR/npm/prune_npmfile.sh" ${prune_args[@]+"${prune_args[@]}"} ${BACKUP_ARGS[@]+"${BACKUP_ARGS[@]}"}
else
  echo "==> Checking for packages not in npmfile (--no-prune: 削除しません)..."
  if [[ -z "$to_remove" ]]; then
    echo "  (no unmanaged packages)"
  else
    echo "  以下のパッケージは npmfile 未管理です（dots npm prune で削除）:"
    while IFS= read -r pkg; do echo "    $pkg"; done <<< "$to_remove"
  fi
fi

# ── キャッシュ更新 ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo ""
  bash "$DOTFILES_DIR/npm/update_npmcache.sh"
fi
