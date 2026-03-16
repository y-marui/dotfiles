#!/usr/bin/env bash
# update_brewcache.sh
# 現在の Homebrew インストール状態を Brewfile.cache に記録する
#
# 動作:
#   brew bundle dump で Brewfile.cache を最新化し、NFC に正規化する
#
# 使い方:
#   bash macos/update_brewcache.sh
#   make brew-cache
#
# brew ラッパー（zshrc）から自動呼び出しされる場合もある

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE_CACHE="$DOTFILES_DIR/macos/Brewfile.cache"

brew bundle dump --force --file="$BREWFILE_CACHE"

# macOS の brew bundle dump は NFD で出力するため NFC に正規化する
python3 -c "
import unicodedata, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    content = f.read()
with open(path, 'w', encoding='utf-8') as f:
    f.write(unicodedata.normalize('NFC', content))
" "$BREWFILE_CACHE"

echo "Brewfile.cache updated."
