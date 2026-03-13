#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/_links.sh
source "$(dirname "${BASH_SOURCE[0]}")/_links.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

count_ok=0
count_broken=0
count_missing=0

for entry in "${LINKS[@]}"; do
  src="${DOTFILES_DIR}/${entry%%|*}"
  dest="${entry##*|}"

  if [[ -L "${dest}" && -e "${dest}" ]]; then
    echo -e "  ${GREEN}OK        ${RESET} ${dest}"
    (( count_ok++ )) || true
  elif [[ -L "${dest}" ]]; then
    echo -e "  ${RED}BROKEN    ${RESET} ${dest} -> $(readlink "${dest}")"
    (( count_broken++ )) || true
  else
    echo -e "  ${YELLOW}NOT LINKED${RESET} ${dest}  (期待: ${src})"
    (( count_missing++ )) || true
  fi
done

echo ""
echo "OK=${count_ok}  BROKEN=${count_broken}  NOT LINKED=${count_missing}"

if [[ "${count_broken}" -gt 0 || "${count_missing}" -gt 0 ]]; then
  exit 1
fi
