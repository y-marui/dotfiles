#!/usr/bin/env bash
# diff_menubarfile.sh
# menubarfile.cache（現在の状態）と menubarfile（管理ファイル）の差分を表示する
#
# 動作:
#   [+cache] controlcenter WiFi 1  → 現在オンだが menubarfile 未記載 → make menubar-sync
#   [-cache] controlcenter WiFi 1  → menubarfile にあるが未適用 → make menubar
#   [changed] controlcenter WiFi cache=1 file=0  → 値が異なる
#   ※ menubarfile に記載のない項目はデフォルト扱いとして無視する
#
# 使い方:
#   bash macos/diff_menubarfile.sh           # 差分を詳細表示
#   bash macos/diff_menubarfile.sh --summary # 1行サマリーのみ出力（zshrc 用）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
MENUBAR_FILE="${PRIVATE_DIR}/macos/menubarfile"
MENUBAR_CACHE="${PRIVATE_DIR}/macos/menubarfile.cache"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$MENUBAR_CACHE" || ! -f "$MENUBAR_FILE" ]]; then
  exit 1
fi

SUMMARY_MODE="$SUMMARY_MODE" MENUBAR_FILE="$MENUBAR_FILE" MENUBAR_CACHE="$MENUBAR_CACHE" \
python3 << 'PYEOF'
import os, sys

MENUBAR_FILE  = os.environ['MENUBAR_FILE']
MENUBAR_CACHE = os.environ['MENUBAR_CACHE']
SUMMARY_MODE  = os.environ['SUMMARY_MODE'] == '1'

def parse(path):
    items = {}      # (domain, name) -> value  ('1' or '0')
    extras = set()  # menuextra paths
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 2:
                continue
            if parts[0] in ('controlcenter', 'systemuiserver') and len(parts) >= 3:
                items[(parts[0], parts[1])] = parts[2]
            elif parts[0] == 'menuextra' and len(parts) >= 2:
                extras.add(parts[1])
    return items, extras

file_items,  file_extras  = parse(MENUBAR_FILE)
cache_items, cache_extras = parse(MENUBAR_CACHE)

changed   = []  # (domain, name, cache_val, file_val)
only_cache = [] # (domain, name, val)  — in cache but not in file
only_file  = [] # (domain, name, val)  — in file but not in cache
only_cache_extras = cache_extras - file_extras
only_file_extras  = file_extras  - cache_extras

all_keys = set(file_items) | set(cache_items)
for key in sorted(all_keys):
    in_cache = key in cache_items
    in_file  = key in file_items
    if in_cache and in_file:
        if cache_items[key] != file_items[key]:
            changed.append((*key, cache_items[key], file_items[key]))
    elif in_cache:
        only_cache.append((*key, cache_items[key]))
    else:
        only_file.append((*key, file_items[key]))

has_diff = bool(changed or only_cache or only_file or only_cache_extras or only_file_extras)

if SUMMARY_MODE:
    if has_diff:
        n = len(changed) + len(only_cache) + len(only_file) + len(only_cache_extras) + len(only_file_extras)
        print(f'menubar {n} 件の差分あり')
    sys.exit(0)

if not has_diff:
    print('No diff: menubarfile.cache と menubarfile は一致しています。')
    sys.exit(0)

if changed:
    print('値が異なる項目 (make menubar で適用):')
    for domain, name, cv, fv in changed:
        print(f'  [changed]  {domain}\t{name}\tcache={cv} file={fv}')
if only_cache:
    print('現在オンだが menubarfile 未記載 (make menubar-sync が必要):')
    for domain, name, val in only_cache:
        print(f'  [+cache]   {domain}\t{name}\t{val}')
if only_file:
    print('menubarfile にあるが未適用 (make menubar で適用):')
    for domain, name, val in only_file:
        print(f'  [-cache]   {domain}\t{name}\t{val}')
if only_cache_extras:
    print('menuExtrasCにあるが menubarfile 未記載 (make menubar-sync が必要):')
    for path in sorted(only_cache_extras):
        print(f'  [+cache menuextra]  {path}')
if only_file_extras:
    print('menubarfile の menuExtras にあるが未適用 (make menubar が必要):')
    for path in sorted(only_file_extras):
        print(f'  [-cache menuextra]  {path}')

sys.exit(1)
PYEOF
