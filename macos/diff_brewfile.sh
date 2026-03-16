#!/usr/bin/env bash
# diff_brewfile.sh
# Brewfile.cache（システム実態）と Brewfile + Brewfile.local（管理ファイル）の差分を表示する
#
# 動作:
#   [+cache] brew "foo"  → システムにインストール済みだが管理ファイル未記載
#   [-files] brew "bar"  → 管理ファイルにあるがシステム未インストール
#
# 使い方:
#   bash macos/diff_brewfile.sh           # 差分を詳細表示
#   bash macos/diff_brewfile.sh --summary # 1行サマリーのみ出力（zlogin 用）
#
# Brewfile.cache が存在しない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE_CACHE="$DOTFILES_DIR/macos/Brewfile.cache"
BREWFILE="$DOTFILES_DIR/macos/Brewfile"
BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$BREWFILE_CACHE" ]]; then
  exit 1
fi

python3 << PYEOF
import re, os, sys

BREWFILE_CACHE = "$BREWFILE_CACHE"
BREWFILE       = "$BREWFILE"
BREWFILE_LOCAL = "$BREWFILE_LOCAL"
SUMMARY_MODE   = $SUMMARY_MODE

ENTRY_PAT = re.compile(r'^(brew|cask|tap|mas|vscode) "([^"]+)"')

def load_entries(path):
    """パスが存在しない場合は空 dict を返す"""
    entries = {}
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                m = ENTRY_PAT.match(line)
                if m:
                    entries[f'{m.group(1)}|{m.group(2)}'] = line.rstrip()
    except FileNotFoundError:
        pass
    return entries

cache_entries  = load_entries(BREWFILE_CACHE)
main_entries   = load_entries(BREWFILE)
local_entries  = load_entries(BREWFILE_LOCAL)
file_entries   = {**main_entries, **local_entries}  # Brewfile + Brewfile.local

only_in_cache = {k: v for k, v in cache_entries.items() if k not in file_entries}
only_in_files = {k: v for k, v in file_entries.items()  if k not in cache_entries}

if SUMMARY_MODE:
    parts = []
    if only_in_cache:
        parts.append(f'+{len(only_in_cache)} cache のみ')
    if only_in_files:
        parts.append(f'-{len(only_in_files)} files のみ')
    if parts:
        print(' / '.join(parts))
    sys.exit(0)

if not only_in_cache and not only_in_files:
    print('No diff: Brewfile.cache と Brewfile は一致しています。')
    sys.exit(0)

if only_in_cache:
    print('インストール済みだが管理ファイル未記載 (+cache のみ):')
    for line in sorted(only_in_cache.values()):
        print(f'  [+cache]  {line}')
    print()
if only_in_files:
    print('管理ファイルにあるがシステム未インストール (-files のみ):')
    for line in sorted(only_in_files.values()):
        print(f'  [-files]  {line}')

sys.exit(1 if (only_in_cache or only_in_files) else 0)
PYEOF
