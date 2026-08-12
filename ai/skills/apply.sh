#!/usr/bin/env bash
# 共通・agent 専用の skill を Claude Code / Codex の個人 skill 配置へ個別リンクする。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${1:-}"
EXTERNAL_FILE="${DOTFILES_DIR}/ai/skills/external.json"
CACHE_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/skills"
STATE_HOME="${CACHE_HOME}/.sources"

case "${AGENT}" in
  claude) SKILL_HOMES=("${HOME}/.claude/skills") ;;
  codex) SKILL_HOMES=("${HOME}/.agents/skills") ;;
  gemini) SKILL_HOMES=("${HOME}/.gemini/skills" "${HOME}/.gemini/config/skills") ;;
  *)
    printf 'usage: %s {claude|codex|gemini}\n' "$0" >&2
    exit 2
    ;;
esac

PYTHON_BIN="$(command -v python3 || echo "python3")"
if [[ "${PYTHON_BIN}" == *".pyenv"* && -x "/usr/bin/python3" ]]; then
  PYTHON_BIN="/usr/bin/python3"
fi

BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)/ai-skills/${AGENT}"
sources_file="$(mktemp)"
trap 'rm -f "${sources_file}"' EXIT
changed=0

mkdir -p "${SKILL_HOMES[@]}"

# 外部 skill は公式 skill-installer で dotfiles 専用キャッシュへ取得し、
# Claude Code / Codex / Gemini から同じ実体を参照する。
while IFS=$'\t' read -r name repo ref path; do
  [[ -n "${name}" ]] || continue
  source_dir="${CACHE_HOME}/${name}"
  state_file="${STATE_HOME}/${name}"
  wanted_state="${repo}"$'\t'"${ref}"$'\t'"${path}"
  current_state=""
  [[ -f "${state_file}" ]] && current_state="$(<"${state_file}")"

  if [[ ! -f "${source_dir}/SKILL.md" || "${current_state}" != "${wanted_state}" ]]; then
    installer="${CODEX_HOME:-${HOME}/.codex}/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    if [[ ! -f "${installer}" ]]; then
      printf 'skill-installer が見つかりません: %s\n' "${installer}" >&2
      exit 1
    fi
    if [[ -e "${source_dir}" || -L "${source_dir}" ]]; then
      mkdir -p "${BACKUP_DIR}/external"
      mv "${source_dir}" "${BACKUP_DIR}/external/${name}"
      printf '  BACKUP  %s -> %s\n' "${source_dir}" "${BACKUP_DIR}/external/${name}"
    fi
    mkdir -p "${CACHE_HOME}" "${STATE_HOME}"
    printf '  INSTALL %s (%s@%s:%s)\n' "${name}" "${repo}" "${ref}" "${path}"
    "${PYTHON_BIN}" "${installer}" --repo "${repo}" --ref "${ref}" --path "${path}" --dest "${CACHE_HOME}"
    printf '%s\n' "${wanted_state}" > "${state_file}"
    changed=1
  fi
  printf '%s\t%s\n' "${name}" "${source_dir}" >> "${sources_file}"
done < <(
  "${PYTHON_BIN}" - "${EXTERNAL_FILE}" "${AGENT}" <<'PYEOF'
import json
import sys

path, agent = sys.argv[1:]
with open(path, encoding="utf-8") as file:
    entries = json.load(file).get("skills", [])

for entry in entries:
    name = entry["name"]
    skill_path = entry["path"]
    if name != skill_path.rstrip("/").rsplit("/", 1)[-1]:
        raise SystemExit(f"external skill name must match path basename: {name}")
    if agent in entry.get("targets", ["claude", "codex", "gemini"]):
        print(
            name,
            entry["repo"],
            entry.get("ref", "main"),
            skill_path,
            sep="\t",
        )
PYEOF
)

for source_home in "${DOTFILES_DIR}/ai/skills" "${DOTFILES_DIR}/ai/${AGENT}/skills"; do
  for skill_file in "${source_home}/"*/SKILL.md; do
    [[ -e "${skill_file}" ]] || continue
    source_dir="$(dirname "${skill_file}")"
    name="$(basename "${source_dir}")"
    printf '%s\t%s\n' "${name}" "${source_dir}" >> "${sources_file}"
  done
done

duplicate_names="$(cut -f1 "${sources_file}" | sort | uniq -d)"
if [[ -n "${duplicate_names}" ]]; then
  printf '共通 skill と %s 専用 skill で名前が重複しています:\n%s\n' \
    "${AGENT}" "${duplicate_names}" >&2
  exit 1
fi

while IFS=$'\t' read -r name source_dir; do
  [[ -n "${name}" ]] || continue
  for skill_home in "${SKILL_HOMES[@]}"; do
    destination="${skill_home}/${name}"

    if [[ -L "${destination}" && "$(readlink "${destination}")" == "${source_dir}" ]]; then
      continue
    fi

    if [[ -e "${destination}" || -L "${destination}" ]]; then
      backup_scope="$(basename "$(dirname "${skill_home}")")-$(basename "${skill_home}")"
      mkdir -p "${BACKUP_DIR}/${backup_scope}"
      mv "${destination}" "${BACKUP_DIR}/${backup_scope}/${name}"
      printf '  BACKUP  %s -> %s\n' "${destination}" "${BACKUP_DIR}/${backup_scope}/${name}"
    fi

    ln -s "${source_dir}" "${destination}"
    printf '  LINK    %s -> %s\n' "${destination}" "${source_dir}"
    changed=1
  done
done < <(sort -k1,1 "${sources_file}")

if [[ "${changed}" -eq 0 ]]; then
  printf '  (already up to date)\n'
fi
