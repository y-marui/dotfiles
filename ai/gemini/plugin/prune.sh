#!/usr/bin/env bash
# 宣言から外れた dotfiles 所有の Antigravity plugin リンクを退避する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/gemini/plugin/plugins.json"
SOURCE_HOME="${DOTFILES_DIR}/ai/gemini/plugin/plugins"
PLUGIN_HOME="${HOME}/.gemini/config/plugins"
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)/antigravity-plugins-pruned"
PYTHON_BIN="$(command -v python3 || echo "python3")"
if [[ "${PYTHON_BIN}" == *".pyenv"* && -x "/usr/bin/python3" ]]; then
  PYTHON_BIN="/usr/bin/python3"
fi

declared_file="$(mktemp)"
trap 'rm -f "${declared_file}"' EXIT
"${PYTHON_BIN}" - "${PLUGINS_FILE}" <<'PYEOF' > "${declared_file}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    for name in json.load(file).get("plugins", []):
        print(name)
PYEOF

changed=0
if [[ -d "${PLUGIN_HOME}" ]]; then
  for destination in "${PLUGIN_HOME}/"*; do
    [[ -L "${destination}" ]] || continue
    name="$(basename "${destination}")"
    grep -Fxq "${name}" "${declared_file}" && continue
    target="$(readlink "${destination}")"
    [[ "${target}" == "${SOURCE_HOME}/"* ]] || continue
    mkdir -p "${BACKUP_DIR}"
    mv "${destination}" "${BACKUP_DIR}/${name}"
    printf '  BACKUP  %s -> %s\n' "${destination}" "${BACKUP_DIR}/${name}"
    changed=1
  done
fi

if [[ "${changed}" -eq 0 ]]; then
  printf '  (nothing to prune)\n'
fi
