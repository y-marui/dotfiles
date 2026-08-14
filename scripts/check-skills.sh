#!/usr/bin/env bash
# dotfiles で管理する全 Agent Skill を公式 validator で検証する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKILL_CREATOR_DIR="${SKILL_CREATOR_DIR:-${CODEX_HOME:-${HOME}/.codex}/skills/.system/skill-creator}"
VALIDATOR="${SKILL_CREATOR_DIR}/scripts/quick_validate.py"

command -v uv >/dev/null 2>&1 || {
  printf 'Error: uv is required.\n' >&2
  exit 1
}

[[ -f "${VALIDATOR}" ]] || {
  printf 'Error: skill validator not found: %s\n' "${VALIDATOR}" >&2
  exit 1
}

skill_dirs=()
while IFS= read -r skill_file; do
  skill_dirs+=("$(dirname "${skill_file}")")
done < <(
  find \
    "${DOTFILES_DIR}/ai/skills" \
    "${DOTFILES_DIR}/ai/claude/skills" \
    "${DOTFILES_DIR}/ai/codex/skills" \
    "${DOTFILES_DIR}/ai/gemini/skills" \
    -mindepth 2 -maxdepth 2 -name SKILL.md -type f 2>/dev/null | sort
)

if [[ "${#skill_dirs[@]}" -eq 0 ]]; then
  printf 'Error: no managed skills found.\n' >&2
  exit 1
fi

for skill_dir in "${skill_dirs[@]}"; do
  printf 'VALIDATE %s\n' "${skill_dir#"${DOTFILES_DIR}/"}"
  uv run --frozen python "${VALIDATOR}" "${skill_dir}"

  scripts_dir="${skill_dir}/scripts"
  if [[ -d "${scripts_dir}" ]] && find "${scripts_dir}" -maxdepth 1 -name 'test_*.py' -type f | grep -q .; then
    printf 'TEST     %s\n' "${scripts_dir#"${DOTFILES_DIR}/"}"
    uv run --frozen python -m unittest discover -s "${scripts_dir}" -p 'test_*.py'
  fi
done

printf 'OK: %d skill(s) validated.\n' "${#skill_dirs[@]}"
