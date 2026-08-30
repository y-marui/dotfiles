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

# cloud.json で claude.ai Skills 登録対象として宣言された skill は、
# computer use（ブラウザGUI操作）やローカル専用MCP・ローカルファイルパスに
# 依存しないことを確認する。claude.ai SkillsはBash・WebFetch・同梱scriptsの
# 実行が可能なサンドボックスを持つため、それら自体は禁止しない
# （実機のweather-check/scripts/sunrise_sunset.pyで確認済み）。
CLOUD_MANIFEST="${DOTFILES_DIR}/ai/skills/cloud.json"
if [[ -f "${CLOUD_MANIFEST}" ]]; then
  cloud_count=0
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    cloud_count=$((cloud_count + 1))
    skill_md=""
    for base in "${DOTFILES_DIR}/ai/skills" "${DOTFILES_DIR}/ai/claude/skills" "${DOTFILES_DIR}/ai/codex/skills" "${DOTFILES_DIR}/ai/gemini/skills"; do
      if [[ -f "${base}/${name}/SKILL.md" ]]; then
        skill_md="${base}/${name}/SKILL.md"
        break
      fi
    done
    if [[ -z "${skill_md}" ]]; then
      printf 'Error: ai/skills/cloud.json references unknown skill: %s\n' "${name}" >&2
      exit 1
    fi

    printf 'CLOUD    %s\n' "${name}"

    if grep -qiE 'computer use|computer-use|コンピュータ操作|ローカルファイル|ローカル専用MCP|ローカルMCP' "${skill_md}"; then
      printf 'Error: %s references local-only tools but is declared as a claude.ai cloud skill\n' "${name}" >&2
      exit 1
    fi
  done < <(
    python3 - "${CLOUD_MANIFEST}" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    for entry in json.load(file).get("skills", []):
        print(entry["name"])
PYEOF
  )
  if [[ "${cloud_count}" -gt 0 ]]; then
    printf 'OK: %d cloud skill(s) portability-checked.\n' "${cloud_count}"
  fi
fi
