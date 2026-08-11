#!/usr/bin/env bash
# 宣言から外れた dotfiles 所有の skill リンクと外部 skill キャッシュを退避する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${1:-}"
EXTERNAL_FILE="${DOTFILES_DIR}/ai/skills/external.json"
CACHE_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/skills"
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)/ai-skills-pruned/${AGENT}"

case "${AGENT}" in
  claude) SKILL_HOME="${HOME}/.claude/skills" ;;
  codex) SKILL_HOME="${HOME}/.agents/skills" ;;
  *)
    printf 'usage: %s {claude|codex}\n' "$0" >&2
    exit 2
    ;;
esac

declared_file="$(mktemp)"
trap 'rm -f "${declared_file}"' EXIT

for source_home in "${DOTFILES_DIR}/ai/skills" "${DOTFILES_DIR}/ai/${AGENT}/skills"; do
  for skill_file in "${source_home}/"*/SKILL.md; do
    [[ -e "${skill_file}" ]] || continue
    basename "$(dirname "${skill_file}")" >> "${declared_file}"
  done
done

python3 - "${EXTERNAL_FILE}" "${AGENT}" <<'PYEOF' >> "${declared_file}"
import json
import sys

path, agent = sys.argv[1:]
with open(path, encoding="utf-8") as file:
    entries = json.load(file).get("skills", [])
for entry in entries:
    if agent in entry.get("targets", ["claude", "codex"]):
        print(entry["name"])
PYEOF
sort -u -o "${declared_file}" "${declared_file}"

changed=0
if [[ -d "${SKILL_HOME}" ]]; then
  for destination in "${SKILL_HOME}/"*; do
    [[ -L "${destination}" ]] || continue
    name="$(basename "${destination}")"
    grep -Fxq "${name}" "${declared_file}" && continue
    target="$(readlink "${destination}")"
    case "${target}" in
      "${DOTFILES_DIR}/ai/skills/"*|"${DOTFILES_DIR}/ai/${AGENT}/skills/"*|"${CACHE_HOME}/"*)
        mkdir -p "${BACKUP_DIR}/links"
        mv "${destination}" "${BACKUP_DIR}/links/${name}"
        printf '  BACKUP  %s -> %s\n' "${destination}" "${BACKUP_DIR}/links/${name}"
        changed=1
        ;;
    esac
  done
fi

# どちらの agent からも参照されず、宣言にもない専用キャッシュだけを退避する。
all_external_file="$(mktemp)"
trap 'rm -f "${declared_file}" "${all_external_file}"' EXIT
python3 - "${EXTERNAL_FILE}" <<'PYEOF' > "${all_external_file}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    entries = json.load(file).get("skills", [])
for entry in entries:
    print(entry["name"])
PYEOF
sort -u -o "${all_external_file}" "${all_external_file}"

if [[ -d "${CACHE_HOME}" ]]; then
  for source_dir in "${CACHE_HOME}/"*; do
    [[ -d "${source_dir}" ]] || continue
    name="$(basename "${source_dir}")"
    grep -Fxq "${name}" "${all_external_file}" && continue
    referenced=false
    for destination in "${HOME}/.agents/skills/${name}" "${HOME}/.claude/skills/${name}"; do
      if [[ -L "${destination}" && "$(readlink "${destination}")" == "${source_dir}" ]]; then
        referenced=true
      fi
    done
    [[ "${referenced}" == true ]] && continue
    mkdir -p "${BACKUP_DIR}/external"
    mv "${source_dir}" "${BACKUP_DIR}/external/${name}"
    [[ ! -e "${CACHE_HOME}/.sources/${name}" ]] || \
      mv "${CACHE_HOME}/.sources/${name}" "${BACKUP_DIR}/external/${name}.source"
    printf '  BACKUP  %s -> %s\n' "${source_dir}" "${BACKUP_DIR}/external/${name}"
    changed=1
  done
fi

if [[ "${changed}" -eq 0 ]]; then
  printf '  (nothing to prune)\n'
fi
