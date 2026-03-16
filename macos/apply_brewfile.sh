#!/usr/bin/env bash
# apply_brewfile.sh
# Brewfile / Brewfile.local の内容をローカルの Homebrew 環境に適用する
#
# 動作:
#   1. brew bundle install — Brewfile にあってローカルにないものをインストール
#   2. brew bundle install — Brewfile.local にあってローカルにないものをインストール（存在する場合）
#   3. brew bundle cleanup — ローカルにあって Brewfile にないものをリストアップ
#                            （--force を付けると確認なしにアンインストール）
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash apply_brewfile.sh [--force]
#
# git pull 後のエイリアス例（.zshrc）:
#   alias dotpull='cd $DOTFILES_DIR && git pull && bash $DOTFILES_DIR/macos/apply_brewfile.sh'

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE="$DOTFILES_DIR/macos/Brewfile"
FORCE=0

for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=1
done

# ── 1. インストール ──────────────────────────────────────────────────────────────
echo "==> Installing packages from Brewfile..."
brew bundle install --file="$BREWFILE"

# ── 2. Brewfile.local のインストール（存在する場合のみ） ───────────────────────
BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"
if [[ -f "$BREWFILE_LOCAL" ]]; then
  echo ""
  echo "==> Installing packages from Brewfile.local..."
  brew bundle install --file="$BREWFILE_LOCAL"
fi

# ── 3. 不要パッケージの削除 ─────────────────────────────────────────────────────
# Brewfile と Brewfile.local を合わせて cleanup（local のパッケージを誤削除しない）
echo ""
echo "==> Checking for packages not in Brewfile or Brewfile.local..."
COMBINED=$(mktemp)
trap 'rm -f "$COMBINED"' EXIT
cat "$BREWFILE" > "$COMBINED"
if [[ -f "$BREWFILE_LOCAL" ]]; then
  cat "$BREWFILE_LOCAL" >> "$COMBINED"
fi
if [[ $FORCE -eq 1 ]]; then
  brew bundle cleanup --force --file="$COMBINED"
else
  brew bundle cleanup --file="$COMBINED"
fi
