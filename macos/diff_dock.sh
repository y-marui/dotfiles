#!/usr/bin/env bash
# diff_dock.sh
# dock.cache（現在の Dock 状態）と dock.sh（管理ファイル）の差分を表示する
#
# 動作:
#   [+cache] /Applications/Foo.app  → Dock にあるが dock.sh 未記載 → make dock-sync
#   [-cache] /Applications/Bar.app  → dock.sh にあるが Dock 未適用 → make dock
#   ※ dock.sh に記載されているが存在しないアプリは無視する（別マシン向け）
#
# 使い方:
#   bash macos/diff_dock.sh           # 差分を詳細表示
#   bash macos/diff_dock.sh --summary # 1行サマリーのみ出力（zlogin 用）
#
# dock.cache または dock.sh が見つからない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_SH="${PRIVATE_DIR}/macos/dock.sh"
DOCK_CACHE="${PRIVATE_DIR}/macos/dock.cache"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$DOCK_CACHE" || ! -f "$DOCK_SH" ]]; then
  exit 1
fi

SUMMARY_MODE="$SUMMARY_MODE" DOCK_SH="$DOCK_SH" DOCK_CACHE="$DOCK_CACHE" \
python3 << 'PYEOF'
import re, os, sys
from pathlib import Path
from urllib.parse import unquote

DOCK_SH      = os.environ['DOCK_SH']
DOCK_CACHE   = os.environ['DOCK_CACHE']
SUMMARY_MODE = os.environ['SUMMARY_MODE'] == '1'

# ── dock.sh をパース ─────────────────────────────────────────────────────────
dock_sh_apps    = []   # _dock_add パス
dock_sh_sidebar = {}   # name -> url

with open(DOCK_SH, encoding='utf-8') as f:
    content = f.read()
for m in re.finditer(r'_dock_add "(.+?)"', content):
    dock_sh_apps.append(m.group(1))
for m in re.finditer(r'_sidebar_add "(.+?)" "(.+?)"', content):
    dock_sh_sidebar[m.group(1)] = m.group(2)

# ── dock.cache をパース ──────────────────────────────────────────────────────
cache_apps    = []   # パス
cache_sidebar = {}   # name -> url

with open(DOCK_CACHE, encoding='utf-8') as f:
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 2:
            continue
        if parts[0] == 'dock':
            cache_apps.append(parts[1])
        elif parts[0] == 'sidebar' and len(parts) >= 3:
            cache_sidebar[parts[1]] = parts[2]

# ── dock.sh のエントリを「このマシンに存在するもの」に限定 ────────────────────
def url_to_path(url):
    return unquote(url).removeprefix('file://').rstrip('/')

existing_sh_apps    = [p for p in dock_sh_apps if Path(p).exists()]
existing_sh_sidebar = {n: u for n, u in dock_sh_sidebar.items()
                       if Path(url_to_path(u)).exists()}

# ── 比較 ─────────────────────────────────────────────────────────────────────
cache_set = set(cache_apps)
sh_set    = set(existing_sh_apps)
only_in_cache = cache_set - sh_set    # dock にあるが dock.sh 未記載
only_in_sh    = sh_set    - cache_set # dock.sh にあるが Dock 未適用

cache_sb_names = set(cache_sidebar.keys())
sh_sb_names    = set(existing_sh_sidebar.keys())
only_in_cache_sb = cache_sb_names - sh_sb_names
only_in_sh_sb    = sh_sb_names    - cache_sb_names

has_diff = bool(only_in_cache or only_in_sh or only_in_cache_sb or only_in_sh_sb)

if SUMMARY_MODE:
    if has_diff:
        n = len(only_in_cache) + len(only_in_sh) + len(only_in_cache_sb) + len(only_in_sh_sb)
        print(f'Dock {n} 件の差分あり')
    sys.exit(0)

if not has_diff:
    print('No diff: dock.cache と dock.sh は一致しています。')
    sys.exit(0)

if only_in_cache:
    print('Dock にあるが dock.sh 未記載 (make dock-sync が必要):')
    for p in sorted(only_in_cache):
        print(f'  [+cache]  {p}')
if only_in_sh:
    print('dock.sh にあるが Dock 未適用 (make dock が必要):')
    for p in sorted(only_in_sh):
        print(f'  [-cache]  {p}')
if only_in_cache_sb:
    print('Sidebar にあるが dock.sh 未記載 (make dock-sync が必要):')
    for n in sorted(only_in_cache_sb):
        print(f'  [+cache sidebar]  {n}')
if only_in_sh_sb:
    print('dock.sh の Sidebar にあるが未適用 (make dock が必要):')
    for n in sorted(only_in_sh_sb):
        print(f'  [-cache sidebar]  {n}')

sys.exit(1)
PYEOF
