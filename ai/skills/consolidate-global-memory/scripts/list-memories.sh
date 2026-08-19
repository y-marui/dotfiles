#!/usr/bin/env bash
# ~/.claude/memory（global）と ~/.claude/projects/*/memory（project別）の
# 全メモリファイルを一覧化する。各行は TSV:
#   scope<TAB>type<TAB>name<TAB>description<TAB>path
# scope は "global" または "project:<project-dir-name>"。
# MEMORY.md（frontmatterを持たないインデックスファイル）は name/type/description が空欄で出力する。
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
GLOBAL_MEMORY_DIR="${CLAUDE_DIR}/memory"
PROJECTS_DIR="${CLAUDE_DIR}/projects"

list_dir() {
  local scope="$1" dir="$2"
  [[ -d "${dir}" ]] || return 0

  local file fields
  for file in "${dir}"/*.md; do
    [[ -e "${file}" ]] || continue
    # frontmatter は現行スキーマ（metadata: 配下に type）と旧スキーマ
    # （type がトップレベル）が混在するため、先頭の --- ブロック内だけを
    # 走査して両方を拾う。MEMORY.md のように frontmatter がない場合は
    # 全フィールド空欄になる。
    fields="$(awk '
      /^---$/ { delim++; next }
      delim == 1 {
        if ($0 ~ /^name: */)        { sub(/^name: */, ""); name = $0 }
        else if ($0 ~ /^description: */) { sub(/^description: */, ""); desc = $0 }
        else if ($0 ~ /^[[:space:]]*type: */) { sub(/^[[:space:]]*type: */, ""); type = $0 }
      }
      delim >= 2 { exit }
      END { printf "%s\t%s\t%s", type, name, desc }
    ' "${file}")"
    printf '%s\t%s\t%s\n' "${scope}" "${fields}" "${file}"
  done
}

list_dir "global" "${GLOBAL_MEMORY_DIR}"

if [[ -d "${PROJECTS_DIR}" ]]; then
  for proj_dir in "${PROJECTS_DIR}"/*/; do
    proj_dir="${proj_dir%/}"
    mem_dir="${proj_dir}/memory"
    [[ -d "${mem_dir}" ]] || continue
    list_dir "project:$(basename "${proj_dir}")" "${mem_dir}"
  done
fi
