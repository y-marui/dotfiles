#!/usr/bin/env bash
# apply_pipxfile.sh
# pipxfile の内容をローカルの pipx 環境に適用する
#
# 動作:
#   1. pipxfile にあって未インストールのものをインストール
#   2. 続けて prune_pipxfile.sh で pipxfile にないものを削除（--no-prune で省略）
#      --no-prune の場合は未管理パッケージを一覧表示するだけで削除しない
#   3. pipxfile.cache を更新
#   --dry-run は何も変更せず、実行した場合の変更予定だけを表示する。
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash pipx/apply_pipxfile.sh [--no-prune] [--dry-run] [--backup-dir DIR]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
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
    *) echo "usage: apply_pipxfile.sh [--no-prune] [--dry-run] [--backup-dir DIR]" >&2; exit 2 ;;
  esac
done

load_names() {
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1" | sort
}

package_spec_for() {
  local name="$1"

  awk -v name="$name" '
    $1 == name {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      print length($0) ? $0 : name
      exit
    }
  ' "$PIPXFILE"
}

installed=$(bash "$DOTFILES_DIR/pipx/update_pipxcache.sh" --print | sort)
to_install=$(comm -13 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$PIPXFILE"))
to_remove=$(comm -23 <(printf '%s\n' "$installed" | grep -v '^\s*$' || true) <(load_names "$PIPXFILE"))

# ── インストール ───────────────────────────────────────────────────────────────
echo "==> Installing packages from pipxfile..."
if [[ -z "$to_install" ]]; then
  echo "  (already up to date)"
else
  while IFS= read -r pkg; do
    package_spec="$(package_spec_for "$pkg")"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  [dry-run] install  $pkg"
    else
      echo "  install  $pkg"
      pipx install "$package_spec"
    fi
  done <<< "$to_install"
fi

# ── 不要パッケージの削除 ───────────────────────────────────────────────────────
echo ""
if [[ "$NO_PRUNE" -eq 0 ]]; then
  prune_args=()
  [[ "$DRY_RUN" -eq 0 ]] || prune_args+=(--dry-run)
  bash "$DOTFILES_DIR/pipx/prune_pipxfile.sh" ${prune_args[@]+"${prune_args[@]}"} ${BACKUP_ARGS[@]+"${BACKUP_ARGS[@]}"}
else
  echo "==> Checking for packages not in pipxfile (--no-prune: 削除しません)..."
  if [[ -z "$to_remove" ]]; then
    echo "  (no unmanaged packages)"
  else
    echo "  以下のパッケージは pipxfile 未管理です（dots pipx prune で削除）:"
    while IFS= read -r pkg; do echo "    $pkg"; done <<< "$to_remove"
  fi
fi

# ── キャッシュ更新 ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo ""
  bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"
fi
