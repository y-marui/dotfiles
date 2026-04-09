#!/usr/bin/env bash
# apply_pipxfile.sh
# pipxfile の内容をローカルの pipx 環境に適用する
#
# 動作:
#   1. pipxfile にあってキャッシュにないものをインストール
#   2. キャッシュにあって pipxfile にないものをリストアップ
#      （--force を付けると確認なしにアンインストール）
#   3. pipxfile.cache を更新
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash pipx/apply_pipxfile.sh [--force]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"
FORCE=0

for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=1
done

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

# ── キャッシュ更新 ─────────────────────────────────────────────────────────────
echo "==> Updating pipxfile.cache..."
bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"

to_install=$(comm -13 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))
to_remove=$(comm -23 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))

# ── インストール ───────────────────────────────────────────────────────────────
echo ""
echo "==> Installing packages from pipxfile..."
if [[ -z "$to_install" ]]; then
  echo "  (already up to date)"
else
  while IFS= read -r pkg; do
    echo "  install  $pkg"
    pipx install "$pkg"
  done <<< "$to_install"
fi

# ── 不要パッケージの削除 ───────────────────────────────────────────────────────
echo ""
echo "==> Checking for packages not in pipxfile..."
if [[ -z "$to_remove" ]]; then
  echo "  (no unmanaged packages)"
elif [[ $FORCE -eq 1 ]]; then
  while IFS= read -r pkg; do
    echo "  uninstall  $pkg"
    pipx uninstall "$pkg"
  done <<< "$to_remove"
else
  echo "  以下のパッケージは pipxfile 未管理です（--force で削除）:"
  while IFS= read -r pkg; do echo "    $pkg"; done <<< "$to_remove"
fi

# ── キャッシュ再更新 ───────────────────────────────────────────────────────────
echo ""
bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"
