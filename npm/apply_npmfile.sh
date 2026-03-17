#!/usr/bin/env bash
# apply_npmfile.sh
# npmfile の内容をローカルの npm グローバル環境に適用する
#
# 動作:
#   1. npmfile にあってキャッシュにないものをインストール
#   2. キャッシュにあって npmfile にないものをリストアップ
#      （--force を付けると確認なしにアンインストール）
#   3. npmfile.cache を更新
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash npm/apply_npmfile.sh [--force]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE="$DOTFILES_DIR/npm/npmfile"
NPMFILE_CACHE="$DOTFILES_DIR/npm/npmfile.cache"
FORCE=0

for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=1
done

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

# ── キャッシュ更新 ─────────────────────────────────────────────────────────────
echo "==> Updating npmfile.cache..."
bash "$DOTFILES_DIR/npm/update_npmcache.sh"

to_install=$(comm -13 <(load_names "$NPMFILE_CACHE") <(load_names "$NPMFILE"))
to_remove=$(comm -23 <(load_names "$NPMFILE_CACHE") <(load_names "$NPMFILE"))

# ── インストール ───────────────────────────────────────────────────────────────
echo ""
echo "==> Installing packages from npmfile..."
if [[ -z "$to_install" ]]; then
  echo "  (already up to date)"
else
  while IFS= read -r pkg; do
    echo "  install  $pkg"
    npm install -g "$pkg"
  done <<< "$to_install"
fi

# ── 不要パッケージの削除 ───────────────────────────────────────────────────────
echo ""
echo "==> Checking for packages not in npmfile..."
if [[ -z "$to_remove" ]]; then
  echo "  (no unmanaged packages)"
elif [[ $FORCE -eq 1 ]]; then
  while IFS= read -r pkg; do
    echo "  uninstall  $pkg"
    npm uninstall -g "$pkg"
  done <<< "$to_remove"
else
  echo "  以下のパッケージは npmfile 未管理です（--force で削除）:"
  while IFS= read -r pkg; do echo "    $pkg"; done <<< "$to_remove"
fi

# ── キャッシュ再更新 ───────────────────────────────────────────────────────────
echo ""
bash "$DOTFILES_DIR/npm/update_npmcache.sh"
