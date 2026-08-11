#!/usr/bin/env bash
# 管理ファイルと、Claude Code / Codex が実際に読む個人 skill の差分を表示する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${1:-}"
SUMMARY_MODE=0
[[ "${2:-}" == "--summary" ]] && SUMMARY_MODE=1

case "${AGENT}" in
  claude) SKILL_HOME="${HOME}/.claude/skills" ;;
  codex) SKILL_HOME="${HOME}/.agents/skills" ;;
  *)
    printf 'usage: %s {claude|codex} [--summary]\n' "$0" >&2
    exit 2
    ;;
esac

SOURCE_HOME="${DOTFILES_DIR}/ai/${AGENT}/skills"
declared_file="$(mktemp)"
actual_file="$(mktemp)"
mismatch_file="$(mktemp)"
trap 'rm -f "${declared_file}" "${actual_file}" "${mismatch_file}"' EXIT

for skill_file in "${SOURCE_HOME}/"*/SKILL.md; do
  [[ -e "${skill_file}" ]] || continue
  source_dir="$(dirname "${skill_file}")"
  name="$(basename "${source_dir}")"
  printf '%s\n' "${name}" >> "${declared_file}"

  destination="${SKILL_HOME}/${name}"
  if [[ ( -e "${destination}" || -L "${destination}" ) && \
    ( ! -L "${destination}" || "$(readlink "${destination}" 2>/dev/null || true)" != "${source_dir}" ) ]]; then
    printf '%s\n' "${name}" >> "${mismatch_file}"
  fi
done

if [[ -d "${SKILL_HOME}" ]]; then
  for destination in "${SKILL_HOME}/"*; do
    [[ -e "${destination}" || -L "${destination}" ]] || continue
    if [[ -f "${destination}/SKILL.md" || -L "${destination}" ]]; then
      basename "${destination}" >> "${actual_file}"
    fi
  done
fi

sort -u -o "${declared_file}" "${declared_file}"
sort -u -o "${actual_file}" "${actual_file}"
sort -u -o "${mismatch_file}" "${mismatch_file}"

python3 - "${declared_file}" "${actual_file}" "${mismatch_file}" "${SUMMARY_MODE}" <<'PYEOF'
import sys

declared_path, actual_path, mismatch_path = sys.argv[1:4]
summary = sys.argv[4] == "1"


def names(path):
    with open(path, encoding="utf-8") as file:
        return {line.strip() for line in file if line.strip()}


declared = names(declared_path)
actual = names(actual_path)
mismatched = names(mismatch_path)
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
    if parts:
        print(" / ".join(parts))
    raise SystemExit(1 if parts else 0)

if not only_actual and not only_files and not mismatched:
    print("No diff: 実際の skill と管理ファイルは一致しています。")
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

raise SystemExit(1)
PYEOF
