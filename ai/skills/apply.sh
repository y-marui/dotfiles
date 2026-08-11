#!/usr/bin/env bash
# 管理対象の skill を Claude Code / Codex の個人 skill 配置へ個別リンクする。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${1:-}"

case "${AGENT}" in
  claude) SKILL_HOME="${HOME}/.claude/skills" ;;
  codex) SKILL_HOME="${HOME}/.agents/skills" ;;
  *)
    printf 'usage: %s {claude|codex}\n' "$0" >&2
    exit 2
    ;;
esac

SOURCE_HOME="${DOTFILES_DIR}/ai/${AGENT}/skills"
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)/ai-skills/${AGENT}"
changed=0

mkdir -p "${SKILL_HOME}"

for skill_file in "${SOURCE_HOME}/"*/SKILL.md; do
  [[ -e "${skill_file}" ]] || continue
  source_dir="$(dirname "${skill_file}")"
  name="$(basename "${source_dir}")"
  destination="${SKILL_HOME}/${name}"

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
done

if [[ "${changed}" -eq 0 ]]; then
  printf '  (already up to date)\n'
fi
