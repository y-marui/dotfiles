#!/usr/bin/env bash
# Homebrewの実際のpin状態をBrewfile-pin.cacheへ記録する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE_PIN_CACHE="${DOTFILES_DIR}/macos/Brewfile-pin.cache"
TEMP_CACHE="$(mktemp)"
trap 'rm -f "${TEMP_CACHE}"' EXIT

while IFS= read -r name; do
  [[ -n "${name}" ]] || continue
  if brew list --formula "${name}" >/dev/null 2>&1; then
    printf 'brew "%s"\n' "${name}" >> "${TEMP_CACHE}"
  elif brew list --cask "${name}" >/dev/null 2>&1; then
    printf 'cask "%s"\n' "${name}" >> "${TEMP_CACHE}"
  else
    printf 'warning: pinned package type could not be resolved: %s\n' "${name}" >&2
  fi
done < <(brew list --pinned)

LC_ALL=C sort -u "${TEMP_CACHE}" > "${BREWFILE_PIN_CACHE}"
echo "Brewfile-pin.cache updated."
