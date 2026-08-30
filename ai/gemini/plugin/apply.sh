#!/usr/bin/env bash
# plugins.json で宣言した Antigravity plugin をグローバル配置へリンクする。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/gemini/plugin/plugins.json"
SOURCE_HOME="${DOTFILES_DIR}/ai/gemini/plugin/plugins"
PLUGIN_HOME="${HOME}/.gemini/config/plugins"
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)/antigravity-plugins"
PYTHON_BIN="python3"

mkdir -p "${PLUGIN_HOME}"
changed=0

while IFS= read -r name; do
  [[ -n "${name}" ]] || continue
  source_dir="${SOURCE_HOME}/${name}"
  destination="${PLUGIN_HOME}/${name}"
  if [[ ! -f "${source_dir}/plugin.json" ]]; then
    printf 'plugin manifest が見つかりません: %s/plugin.json\n' "${source_dir}" >&2
    exit 1
  fi
  if [[ -L "${destination}" && "$(readlink "${destination}")" == "${source_dir}" ]]; then
    continue
  fi
  if [[ -e "${destination}" || -L "${destination}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    mv "${destination}" "${BACKUP_DIR}/${name}"
    printf '  BACKUP  %s -> %s\n' "${destination}" "${BACKUP_DIR}/${name}"
  fi
  ln -s "${source_dir}" "${destination}"
  printf '  LINK    %s -> %s\n' "${destination}" "${source_dir}"
  changed=1
done < <("${PYTHON_BIN}" - "${PLUGINS_FILE}" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    for name in json.load(file).get("plugins", []):
        print(name)
PYEOF
)

if [[ "${changed}" -eq 0 ]]; then
  printf '  (already up to date)\n'
fi
