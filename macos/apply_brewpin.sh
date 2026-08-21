#!/usr/bin/env bash
# Brewfile-pinの宣言に実際のHomebrew pin状態を一致させる。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE_PIN="${DOTFILES_DIR}/macos/Brewfile-pin"
BREWFILE_PIN_CACHE="${DOTFILES_DIR}/macos/Brewfile-pin.cache"

bash "${DOTFILES_DIR}/macos/update_brewpin_cache.sh" >/dev/null

while IFS=$'\t' read -r action package_type name; do
  [[ -n "${action}" ]] || continue
  case "${package_type}" in
    brew) type_option="--formula" ;;
    cask) type_option="--cask" ;;
    *) printf 'error: unknown pin package type: %s\n' "${package_type}" >&2; exit 1 ;;
  esac
  printf '  %s  %s (%s)\n' "${action}" "${name}" "${package_type}"
  case "${action}" in
    pin) brew pin "${type_option}" "${name}" ;;
    unpin) brew unpin "${type_option}" "${name}" ;;
    *) printf 'error: unknown pin action: %s\n' "${action}" >&2; exit 1 ;;
  esac
done < <(
  python3 - "${BREWFILE_PIN}" "${BREWFILE_PIN_CACHE}" <<'PYEOF'
import re
import sys
from pathlib import Path

pin_path, cache_path = map(Path, sys.argv[1:])
entry_pattern = re.compile(r'^(brew|cask) "([^"]+)"')


def load_entries(path):
    entries = set()
    if not path.exists():
        return entries
    for line in path.read_text(encoding="utf-8").splitlines():
        match = entry_pattern.match(line)
        if match:
            entries.add((match.group(1), match.group(2)))
    return entries


declared = load_entries(pin_path)
actual = load_entries(cache_path)
for package_type, name in sorted(declared - actual):
    print(f"pin\t{package_type}\t{name}")
for package_type, name in sorted(actual - declared):
    print(f"unpin\t{package_type}\t{name}")
PYEOF
)

bash "${DOTFILES_DIR}/macos/update_brewpin_cache.sh"
