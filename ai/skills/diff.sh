#!/usr/bin/env bash
# 共通・agent 専用の管理ファイルと、実際に探索される個人 skill の差分を表示する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${1:-}"
EXTERNAL_FILE="${DOTFILES_DIR}/ai/skills/external.json"
CACHE_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/skills"
SUMMARY_MODE=0
[[ "${2:-}" == "--summary" ]] && SUMMARY_MODE=1

case "${AGENT}" in
  claude) SKILL_HOMES=("${HOME}/.claude/skills") ;;
  codex) SKILL_HOMES=("${HOME}/.agents/skills") ;;
  gemini) SKILL_HOMES=("${HOME}/.gemini/skills" "${HOME}/.gemini/config/skills") ;;
  *)
    printf 'usage: %s {claude|codex|gemini} [--summary]\n' "$0" >&2
    exit 2
    ;;
esac

PYTHON_BIN="$(command -v python3 || echo "python3")"
if [[ "${PYTHON_BIN}" == *".pyenv"* && -x "/usr/bin/python3" ]]; then
  PYTHON_BIN="/usr/bin/python3"
fi

sources_file="$(mktemp)"
declared_file="$(mktemp)"
actual_file="$(mktemp)"
mismatch_file="$(mktemp)"
codex_installed_file="$(mktemp)"
source_missing_file="$(mktemp)"
trap 'rm -f "${sources_file}" "${declared_file}" "${actual_file}" "${mismatch_file}" "${codex_installed_file}" "${source_missing_file}"' EXIT

"${PYTHON_BIN}" - "${EXTERNAL_FILE}" "${AGENT}" "${CACHE_HOME}" <<'PYEOF' >> "${sources_file}"
import json
import sys

path, agent, cache_home = sys.argv[1:]
with open(path, encoding="utf-8") as file:
    entries = json.load(file).get("skills", [])
for entry in entries:
    if agent in entry.get("targets", ["claude", "codex", "gemini"]):
        print(entry["name"], f"{cache_home}/{entry['name']}", sep="\t")
PYEOF

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
  printf '%s\n' "${name}" >> "${declared_file}"
  [[ -f "${source_dir}/SKILL.md" ]] || printf '%s\n' "${name}" >> "${source_missing_file}"

  for skill_home in "${SKILL_HOMES[@]}"; do
    destination="${skill_home}/${name}"
    if [[ ! -e "${destination}" && ! -L "${destination}" ]]; then
      printf '%s\n' "${name}" >> "${mismatch_file}"
    elif [[ ! -L "${destination}" || \
      "$(readlink "${destination}" 2>/dev/null || true)" != "${source_dir}" ]]; then
      printf '%s\n' "${name}" >> "${mismatch_file}"
    fi
  done
done < <(sort -k1,1 "${sources_file}")

for skill_home in "${SKILL_HOMES[@]}"; do
  if [[ ! -d "${skill_home}" ]]; then
    continue
  fi
  for destination in "${skill_home}/"*; do
    [[ -e "${destination}" || -L "${destination}" ]] || continue
    if [[ -f "${destination}/SKILL.md" || -L "${destination}" ]]; then
      basename "${destination}" >> "${actual_file}"
    fi
  done
done

# Codex の正規追加先は ~/.agents/skills。~/.codex/skills は Codex 自身や
# skill-installer が使うため、apply では触らず .system 以外を追加済み skill として検知する。
if [[ "${AGENT}" == "codex" && -d "${HOME}/.codex/skills" ]]; then
  for destination in "${HOME}/.codex/skills/"*; do
    [[ -e "${destination}" || -L "${destination}" ]] || continue
    [[ "$(basename "${destination}")" == ".system" ]] && continue
    if [[ -f "${destination}/SKILL.md" || -L "${destination}" ]]; then
      basename "${destination}" >> "${codex_installed_file}"
    fi
  done
fi

sort -u -o "${declared_file}" "${declared_file}"
sort -u -o "${actual_file}" "${actual_file}"
sort -u -o "${mismatch_file}" "${mismatch_file}"
sort -u -o "${codex_installed_file}" "${codex_installed_file}"
sort -u -o "${source_missing_file}" "${source_missing_file}"

"${PYTHON_BIN}" - "${declared_file}" "${actual_file}" "${mismatch_file}" \
  "${codex_installed_file}" "${source_missing_file}" "${SUMMARY_MODE}" "${AGENT}" <<'PYEOF'
import sys

declared_path, actual_path, mismatch_path, codex_installed_path, source_missing_path = sys.argv[1:6]
summary = sys.argv[6] == "1"
agent = sys.argv[7]
agent_label = "Claude Code" if agent == "claude" else ("Codex" if agent == "codex" else "Gemini/Antigravity")


def names(path):
    with open(path, encoding="utf-8") as file:
        return {line.strip() for line in file if line.strip()}


declared = names(declared_path)
actual = names(actual_path)
mismatched = names(mismatch_path)
codex_installed = names(codex_installed_path)
source_missing = names(source_missing_path)
only_actual = sorted(actual - declared)
only_files = sorted(declared - actual)

if summary:
    parts = []
    if only_actual:
        parts.append(f"+{len(only_actual)} actual のみ")
    if only_files:
        parts.append(f"-{len(only_files)} files のみ")
    if mismatched:
        parts.append(f"~{len(mismatched)} link 不一致")
    if codex_installed:
        parts.append(f"+{len(codex_installed)} ~/.codex/skills")
    if source_missing:
        parts.append(f"~{len(source_missing)} source 不足")
    if parts:
        print(" / ".join(parts))
    raise SystemExit(1 if parts else 0)

if not only_actual and not only_files and not mismatched and not codex_installed and not source_missing:
    location = "~/.claude/skills" if agent == "claude" else ("~/.agents/skills" if agent == "codex" else "~/.gemini/skills and ~/.gemini/config/skills")
    print(f"No diff: 管理対象の共通・{agent_label}専用 skill と {location} は一致しています。")
    raise SystemExit(0)

if only_actual:
    print("追加済みだが dotfiles 未記載 (+actual のみ):")
    for name in only_actual:
        print(f"  [+actual]  {name}")
    print()
if only_files:
    print("dotfiles にあるが未配置 (-files のみ):")
    for name in only_files:
        print(f"  [-files]  {name}")
    print()
if mismatched:
    print("管理対象だがリンク先が不一致 (~link):")
    for name in sorted(mismatched):
        print(f"  [~link]    {name}")
    print()
if codex_installed:
    print("Codex 側で追加されている skill (~/.codex/skills、.system は除外):")
    for name in sorted(codex_installed):
        print(f"  [+codex]   {name}")
    print()
if source_missing:
    print("外部 skill の取得元がありません (~source):")
    for name in sorted(source_missing):
        print(f"  [~source]  {name}")

raise SystemExit(1)
PYEOF
