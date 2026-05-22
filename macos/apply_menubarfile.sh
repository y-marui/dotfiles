#!/usr/bin/env bash
# apply_menubarfile.sh
# menubarfile の設定を defaults write で反映し SystemUIServer を再起動する
#
# 使い方:
#   bash macos/apply_menubarfile.sh
#   make menubar

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
MENUBAR_FILE="${PRIVATE_DIR}/macos/menubarfile"

if [[ ! -f "$MENUBAR_FILE" ]]; then
  printf 'Error: %s not found. Run "make menubar-sync" first.\n' "$MENUBAR_FILE" >&2
  exit 1
fi

MENUBAR_FILE="$MENUBAR_FILE" python3 - <<'PYEOF'
import os, subprocess, sys

menubar_file = os.environ['MENUBAR_FILE']
errors = 0

def defaults_write_bool(domain, key, value):
    flag = '-bool true' if value == '1' else '-bool false'
    r = subprocess.run(
        ['defaults', 'write', domain, key, '--', ('true' if value == '1' else 'false')],
        capture_output=True
    )
    if r.returncode != 0:
        print(f'Error: defaults write {domain} "{key}" failed', file=sys.stderr)
        return False
    return True

extras = []
with open(menubar_file, encoding='utf-8') as f:
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 2:
            continue
        if parts[0] == 'controlcenter' and len(parts) >= 3:
            key = f'NSStatusItem VisibleCC {parts[1]}'
            if not defaults_write_bool('com.apple.controlcenter', key, parts[2]):
                errors += 1
        elif parts[0] == 'systemuiserver' and len(parts) >= 3:
            key = f'NSStatusItem VisibleCC {parts[1]}'
            if not defaults_write_bool('com.apple.systemuiserver', key, parts[2]):
                errors += 1
        elif parts[0] == 'menuextra' and len(parts) >= 2:
            extras.append(parts[1])

if extras:
    r = subprocess.run(
        ['defaults', 'write', 'com.apple.systemuiserver', 'menuExtras', '-array'] + extras,
        capture_output=True
    )
    if r.returncode != 0:
        print('Error: failed to write menuExtras', file=sys.stderr)
        errors += 1

sys.exit(1 if errors else 0)
PYEOF

killall SystemUIServer 2>/dev/null || true
export DOTFILES_DIR
bash "$DOTFILES_DIR/macos/update_menubarcache.sh"
printf '%s\n' "menubarfile applied."
