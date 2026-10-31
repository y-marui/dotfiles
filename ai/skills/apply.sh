#!/usr/bin/env bash
# 共通・agent 専用の skill を Claude Code / Codex の個人 skill 配置へ個別リンクする。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${1:-}"
PUBLIC_EXTERNAL_FILE="${DOTFILES_EXTERNAL_FILE:-${DOTFILES_DIR}/ai/skills/external.json}"
PRIVATE_EXTERNAL_FILE="${DOTFILES_PRIVATE_EXTERNAL_FILE:-${DOTFILES_DIR}-private/ai/skills/external.json}"
# An explicit public override retains the isolated/cloud manifest behavior.
if [[ -n "${DOTFILES_EXTERNAL_FILE:-}" && -z "${DOTFILES_PRIVATE_EXTERNAL_FILE:-}" ]]; then
  PRIVATE_EXTERNAL_FILE=""
fi
EXTERNAL_FILE="$(mktemp)"
trap 'rm -f "${EXTERNAL_FILE}"' EXIT
manifest_args=(--public "${PUBLIC_EXTERNAL_FILE}")
[[ -z "${PRIVATE_EXTERNAL_FILE}" ]] || manifest_args+=(--private "${PRIVATE_EXTERNAL_FILE}")
python3 "${DOTFILES_DIR}/ai/skills/external_manifest.py" "${manifest_args[@]}" > "${EXTERNAL_FILE}"
# 指定時は、このJSON（{"skills": ["name", ...]}）に載る skill だけを対象にする。
# Claude Code のクラウドセッション（docs/cloud-sessions.md）が使う。未指定なら全件。
SKILL_SELECT_FILE="${SKILL_SELECT_FILE:-}"
CACHE_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/skills"
STATE_HOME="${CACHE_HOME}/.sources"

case "${AGENT}" in
  claude) SKILL_HOMES=("${HOME}/.claude/skills") ;;
  codex) SKILL_HOMES=("${HOME}/.agents/skills") ;;
  *)
    printf 'usage: %s {claude|codex}\n' "$0" >&2
    exit 2
    ;;
esac

PYTHON_BIN="python3"

selected_names_file=""
if [[ -n "${SKILL_SELECT_FILE}" ]]; then
  selected_names_file="$(mktemp)"
  "${PYTHON_BIN}" - "${SKILL_SELECT_FILE}" > "${selected_names_file}" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    for name in json.load(file).get("skills", []):
        print(name)
PYEOF
fi

is_selected() {
  [[ -z "${selected_names_file}" ]] || grep -qxF -- "$1" "${selected_names_file}"
}

# 公式 skill-installer（Codex 同梱）が無い環境（Linux のクラウド VM 等）向けの代替。
# 固定した ref の該当パスだけを git で取得して、キャッシュへ置く。
install_external_with_git() {
  local name="$1" repo="$2" ref="$3" path="$4"
  local base="${SKILL_GIT_BASE:-https://github.com}" tmp status=0
  tmp="$(mktemp -d)"
  if git clone --quiet --no-checkout --filter=blob:none "${base}/${repo}.git" "${tmp}/repo" \
    && { git -C "${tmp}/repo" checkout --quiet "${ref}" -- "${path}" 2>/dev/null \
      || git -C "${tmp}/repo" checkout --quiet "origin/${ref}" -- "${path}"; } \
    && [[ -f "${tmp}/repo/${path}/SKILL.md" ]]; then
    mkdir -p "${CACHE_HOME}"
    cp -R "${tmp}/repo/${path}" "${CACHE_HOME}/${name}"
  else
    status=1
  fi
  rm -rf "${tmp}"
  return "${status}"
}

BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d%H%M%S)/ai-skills/${AGENT}"
sources_file="$(mktemp)"
trap 'rm -f "${EXTERNAL_FILE}" "${sources_file}" "${selected_names_file:-}"' EXIT
changed=0

mkdir -p "${SKILL_HOMES[@]}"

# 外部 skill は公式 skill-installer で dotfiles 専用キャッシュへ取得し、
# Claude Code / Codex から同じ実体を参照する。
while IFS=$'\t' read -r name repo ref path; do
  [[ -n "${name}" ]] || continue
  source_dir="${CACHE_HOME}/${name}"
  state_file="${STATE_HOME}/${name}"
  wanted_state="${repo}"$'\t'"${ref}"$'\t'"${path}"
  current_state=""
  [[ -f "${state_file}" ]] && current_state="$(<"${state_file}")"

  if [[ ! -f "${source_dir}/SKILL.md" || "${current_state}" != "${wanted_state}" ]]; then
    installer="${CODEX_HOME:-${HOME}/.codex}/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    if [[ ! -f "${installer}" && -n "${SKILL_SELECT_FILE}" ]]; then
      installer=""
    elif [[ ! -f "${installer}" ]]; then
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
    if [[ -n "${installer}" ]]; then
      "${PYTHON_BIN}" "${installer}" --repo "${repo}" --ref "${ref}" --path "${path}" --dest "${CACHE_HOME}"
    else
      install_external_with_git "${name}" "${repo}" "${ref}" "${path}" || {
        printf '外部 skill を取得できません: %s\n' "${name}" >&2
        exit 1
      }
    fi
    printf '%s\n' "${wanted_state}" > "${state_file}"
    changed=1
  fi
  printf '%s\t%s\n' "${name}" "${source_dir}" >> "${sources_file}"
done < <(
  "${PYTHON_BIN}" - "${EXTERNAL_FILE}" "${AGENT}" "${SKILL_SELECT_FILE}" <<'PYEOF'
import json
import sys

path, agent, select_path = sys.argv[1:]
with open(path, encoding="utf-8") as file:
    entries = json.load(file).get("skills", [])
if select_path:
    with open(select_path, encoding="utf-8") as file:
        selected = set(json.load(file).get("skills", []))
    entries = [entry for entry in entries if entry["name"] in selected]

for entry in entries:
    name = entry["name"]
    skill_path = entry["path"]
    if name != skill_path.rstrip("/").rsplit("/", 1)[-1]:
        raise SystemExit(f"external skill name must match path basename: {name}")
    if agent in entry.get("targets", ["claude", "codex"]):
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
    is_selected "${name}" || continue
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
