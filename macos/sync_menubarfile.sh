#!/usr/bin/env bash
# sync_menubarfile.sh
# 現在のメニューバー状態を menubarfile に書き出し、menubarfile.cache を更新する
#
# 使い方:
#   bash macos/sync_menubarfile.sh
#   make menubar-sync

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
MENUBAR_FILE="${PRIVATE_DIR}/macos/menubarfile"

MENUBAR_FILE="$MENUBAR_FILE" python3 - <<'PYEOF'
import os, subprocess, plistlib

menubar_file = os.environ['MENUBAR_FILE']
lines = []

def read_plist(domain):
    r = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True)
    if r.returncode != 0:
        return {}
    try:
        return plistlib.loads(r.stdout)
    except Exception:
        return {}

cc = read_plist('com.apple.controlcenter')
for k, v in sorted(cc.items()):
    if k.startswith('NSStatusItem VisibleCC '):
        item = k.removeprefix('NSStatusItem VisibleCC ')
        lines.append(f'controlcenter\t{item}\t{"1" if v else "0"}')

sui = read_plist('com.apple.systemuiserver')
for k, v in sorted(sui.items()):
    if k.startswith('NSStatusItem VisibleCC '):
        item = k.removeprefix('NSStatusItem VisibleCC ')
        lines.append(f'systemuiserver\t{item}\t{"1" if v else "0"}')
    elif k == 'menuExtras' and isinstance(v, list):
        for path in sorted(v):
            lines.append(f'menuextra\t{path}')

with open(menubar_file, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + ('\n' if lines else ''))
PYEOF

export DOTFILES_DIR
bash "$DOTFILES_DIR/macos/update_menubarcache.sh"
printf '%s\n' "menubarfile synced."
