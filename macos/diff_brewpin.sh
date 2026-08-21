#!/usr/bin/env bash
# Brewfile-pin（宣言）とBrewfile-pin.cache（実際のpin状態）を比較する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE_PIN="${DOTFILES_DIR}/macos/Brewfile-pin"
BREWFILE_PIN_CACHE="${DOTFILES_DIR}/macos/Brewfile-pin.cache"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

[[ -f "${BREWFILE_PIN_CACHE}" ]] || exit 1

python3 - "${BREWFILE_PIN}" "${BREWFILE_PIN_CACHE}" "${SUMMARY_MODE}" <<'PYEOF'
import re
import sys
from pathlib import Path

pin_path, cache_path = map(Path, sys.argv[1:3])
summary = sys.argv[3] == "1"
entry_pattern = re.compile(r'^(brew|cask) "([^"]+)"')


def load_entries(path):
    entries = {}
    if not path.exists():
        return entries
    for line in path.read_text(encoding="utf-8").splitlines():
        match = entry_pattern.match(line)
        if match:
            entries[(match.group(1), match.group(2))] = line
    return entries


declared = load_entries(pin_path)
actual = load_entries(cache_path)
only_actual = {key: value for key, value in actual.items() if key not in declared}
only_declared = {key: value for key, value in declared.items() if key not in actual}

if summary:
    parts = []
    if only_actual:
        parts.append(f"+{len(only_actual)} cache のみ")
    if only_declared:
        parts.append(f"-{len(only_declared)} files のみ")
    if parts:
        print(" / ".join(parts))
    raise SystemExit(1 if parts else 0)

if not only_actual and not only_declared:
    print("No diff: Brewfile-pin.cache と Brewfile-pin は一致しています。")
    raise SystemExit(0)

if only_actual:
    print("pin済みだがBrewfile-pin未記載 (+cache のみ):")
    for line in sorted(only_actual.values()):
        print(f"  [+cache]  {line}")
    print()
if only_declared:
    print("Brewfile-pinにあるが未pin (-files のみ):")
    for line in sorted(only_declared.values()):
        print(f"  [-files]  {line}")

raise SystemExit(1)
PYEOF
