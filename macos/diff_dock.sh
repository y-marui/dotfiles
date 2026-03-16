#!/usr/bin/env bash
# diff_dock.sh
# dock.cache（現在の Dock 状態）と dock ファイル（管理ファイル）の差分を表示する
#
# 動作:
#   [+cache] /Applications/Foo.app  → Dock にあるが dock 未記載 → make dock-sync
#   [-cache] /Applications/Bar.app  → dock にあるが Dock 未適用 → make dock
#   ※ dock に記載されているが存在しないアプリは無視する（別マシン向け）
#
# 使い方:
#   bash macos/diff_dock.sh           # 差分を詳細表示
#   bash macos/diff_dock.sh --summary # 1行サマリーのみ出力（zlogin 用）
#
# dock.cache または dock ファイルが見つからない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_FILE="${PRIVATE_DIR}/macos/dock"
DOCK_CACHE="${PRIVATE_DIR}/macos/dock.cache"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$DOCK_CACHE" || ! -f "$DOCK_FILE" ]]; then
  exit 1
fi

SUMMARY_MODE="$SUMMARY_MODE" DOCK_FILE="$DOCK_FILE" DOCK_CACHE="$DOCK_CACHE" \
python3 << 'PYEOF'
import os, sys
from pathlib import Path
from urllib.parse import unquote

DOCK_FILE    = os.environ['DOCK_FILE']
DOCK_CACHE   = os.environ['DOCK_CACHE']
SUMMARY_MODE = os.environ['SUMMARY_MODE'] == '1'

def parse_dock_file(path):
    apps    = []
    sidebar = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 2:
                continue
            if parts[0] == 'dock':
                apps.append(parts[1])
            elif parts[0] == 'sidebar' and len(parts) >= 3:
                sidebar[parts[1]] = parts[2]
    return apps, sidebar

def url_to_path(url):
    return unquote(url).removeprefix('file://').rstrip('/')

dock_apps,    dock_sidebar  = parse_dock_file(DOCK_FILE)
cache_apps,   cache_sidebar = parse_dock_file(DOCK_CACHE)

# ── dock ファイルのエントリを「このマシンに存在するもの」に限定 ────────────────
existing_dock_apps    = [p for p in dock_apps if Path(p).exists()]
existing_dock_sidebar = {n: u for n, u in dock_sidebar.items()
                         if Path(url_to_path(u)).exists()}

# ── 比較 ─────────────────────────────────────────────────────────────────────
cache_set = set(cache_apps)
dock_set  = set(existing_dock_apps)
only_in_cache = cache_set - dock_set   # Dock にあるが dock 未記載
only_in_dock  = dock_set  - cache_set  # dock にあるが Dock 未適用

cache_sb_names = set(cache_sidebar.keys())
dock_sb_names  = set(existing_dock_sidebar.keys())
only_in_cache_sb = cache_sb_names - dock_sb_names
only_in_dock_sb  = dock_sb_names  - cache_sb_names

has_diff = bool(only_in_cache or only_in_dock or only_in_cache_sb or only_in_dock_sb)

if SUMMARY_MODE:
    if has_diff:
        n = len(only_in_cache) + len(only_in_dock) + len(only_in_cache_sb) + len(only_in_dock_sb)
        print(f'Dock {n} 件の差分あり')
    sys.exit(0)

if not has_diff:
    print('No diff: dock.cache と dock は一致しています。')
    sys.exit(0)

if only_in_cache:
    print('Dock にあるが dock 未記載 (make dock-sync が必要):')
    for p in sorted(only_in_cache):
        print(f'  [+cache]  {p}')
if only_in_dock:
    print('dock にあるが Dock 未適用 (make dock が必要):')
    for p in sorted(only_in_dock):
        print(f'  [-cache]  {p}')
if only_in_cache_sb:
    print('Sidebar にあるが dock 未記載 (make dock-sync が必要):')
    for n in sorted(only_in_cache_sb):
        print(f'  [+cache sidebar]  {n}')
if only_in_dock_sb:
    print('dock の Sidebar にあるが未適用 (make dock が必要):')
    for n in sorted(only_in_dock_sb):
        print(f'  [-cache sidebar]  {n}')

sys.exit(1)
PYEOF
