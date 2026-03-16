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

# ── 4. mas アンインストール対象の警告 ────────────────────────────────────────────
# brew bundle cleanup は mas を対象外にするため、手動対応が必要なものを表示する
if command -v mas &>/dev/null; then
  echo ""
  echo "==> Checking for mas apps not in Brewfile..."
  # Brewfile(s) に記載されている mas ID を収集
  brewfile_ids=$(grep -h '^mas ' "$COMBINED" | grep -oE 'id: [0-9]+' | grep -oE '[0-9]+' || true)
  # インストール済み mas アプリと照合
  unmanaged=""
  while IFS= read -r line; do
    id=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | cut -d' ' -f2-)
    if ! echo "$brewfile_ids" | grep -qx "$id"; then
      unmanaged="${unmanaged}  $id  $name\n"
    fi
  done < <(mas list 2>/dev/null || true)
  if [[ -n "$unmanaged" ]]; then
    echo "WARNING: The following App Store apps are installed but not in Brewfile." >&2
    echo "         brew bundle cleanup does not uninstall mas apps — remove them manually:" >&2
    printf "%b" "$unmanaged" >&2
    echo "         Run 'mas uninstall <id>' first, then 'make brew-cache' to update the cache." >&2
  else
    echo "All installed mas apps are listed in Brewfile."
  fi
fi
