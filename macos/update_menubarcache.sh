#!/usr/bin/env bash
# update_menubarcache.sh
# 現在のメニューバー状態を menubarfile.cache に記録する
#
# 動作:
#   NSStatusItem VisibleCC キー（controlcenter / systemuiserver）と
#   menuExtras リストを取得して menubarfile.cache に書き出す
#
# 使い方:
#   bash macos/update_menubarcache.sh
#   make menubar-cache

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
SNAPSHOT="${PRIVATE_DIR}/macos/menubarfile.cache"

SNAPSHOT="$SNAPSHOT" python3 - <<'PYEOF'
import os, subprocess, plistlib, sys

snapshot = os.environ['SNAPSHOT']
lines = []

def read_plist(domain):
    r = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True)
    if r.returncode != 0:
        return {}
    try:
        return plistlib.loads(r.stdout)
    except Exception:
        return {}

# com.apple.controlcenter — NSStatusItem VisibleCC
cc = read_plist('com.apple.controlcenter')
for k, v in sorted(cc.items()):
    if k.startswith('NSStatusItem VisibleCC '):
        item = k.removeprefix('NSStatusItem VisibleCC ')
        lines.append(f'controlcenter\t{item}\t{"1" if v else "0"}')

# com.apple.systemuiserver — NSStatusItem VisibleCC + menuExtras
sui = read_plist('com.apple.systemuiserver')
for k, v in sorted(sui.items()):
    if k.startswith('NSStatusItem VisibleCC '):
        item = k.removeprefix('NSStatusItem VisibleCC ')
        lines.append(f'systemuiserver\t{item}\t{"1" if v else "0"}')
    elif k == 'menuExtras' and isinstance(v, list):
        for path in sorted(v):
            lines.append(f'menuextra\t{path}')

with open(snapshot, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + ('\n' if lines else ''))

PYEOF

printf '%s\n' "menubarfile.cache updated."
