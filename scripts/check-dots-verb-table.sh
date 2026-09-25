#!/usr/bin/env bash
set -euo pipefail

# scripts/check-dots-verb-table.sh
# dots の動詞テーブルの整合性を検証する。
#   1. README.md の動詞表（apply/diff/sync/merge/prune/cache × ドメイン）の各セルが、
#      bin/unix/_dots-verbs.sh のテーブル（`dots verbs`）と一致する
#      （◯ = ok、N/A（理由） = na、未実装 = todo）
#   2. bin/windows/dots.ps1 の $verbSpecs（ghq / winget）が Unix 側と一致する
#   3. README に載っていないドメイン、テーブルに無いドメインがない
# 動詞テーブルを正本とし、表の書き写し間違い・実装追加時の更新漏れを防ぐ。

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="${DOTFILES_DIR}/README.md"
PS1_FILE="${DOTFILES_DIR}/bin/windows/dots.ps1"
VERBS="apply diff sync merge prune cache"

matrix="$(bash "${DOTFILES_DIR}/bin/unix/dots" verbs)"

errors=0
fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

state_of() {
  printf '%s\n' "${matrix}" | awk -F'\t' -v d="$1" -v v="$2" '$1==d && $2==v { print $3 }'
}

spec_of() {
  local domain="$1" verb spec=""
  for verb in ${VERBS}; do
    spec="${spec:+${spec} }${verb}=$(state_of "${domain}" "${verb}")"
  done
  printf '%s' "${spec}"
}

trim() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# セルの状態（ok / na / todo）。書式に合わないセルは "invalid"。
cell_state() {
  local cell
  cell="$(printf '%s' "$1" | trim)"
  case "${cell}" in
    ◯*) echo ok ;;
    N/A（*) echo na ;;
    未実装*) echo todo ;;
    *) echo invalid ;;
  esac
}

# ── 1. README の動詞表 ────────────────────────────────────────────────────────
# ヘッダー行「| コマンド | apply | ...」から「| 標準動作 |」行の手前までを読む。
rows="$(awk '
  /^\| コマンド \| apply \|/ { in_table = 1; next }
  in_table && /^\| 標準動作/ { exit }
  in_table && /^\| `dots / { print }
' "${README}")"

if [[ -z "${rows}" ]]; then
  fail "README.md に動詞表（| コマンド | apply | ... ）が見つからない"
fi

readme_domains=""
while IFS= read -r row; do
  [[ -n "${row}" ]] || continue
  first_cell="$(printf '%s' "${row}" | awk -F'|' '{ print $2 }')"
  domains="$(printf '%s' "${first_cell}" | grep -o 'dots [a-z]*' | awk '{ print $2 }' | tr '\n' ' ')"
  index=3
  for verb in ${VERBS}; do
    cell="$(printf '%s' "${row}" | awk -F'|' -v i="${index}" '{ print $i }')"
    actual="$(cell_state "${cell}")"
    if [[ "${actual}" == invalid ]]; then
      fail "README の動詞表: '$(printf '%s' "${first_cell}" | trim)' の ${verb} セルが ◯ / N/A（理由） / 未実装 のいずれでもない: $(printf '%s' "${cell}" | trim)"
    else
      for domain in ${domains}; do
        expected="$(state_of "${domain}" "${verb}")"
        if [[ -z "${expected}" ]]; then
          fail "README の動詞表にあるドメイン '${domain}' が dots の動詞テーブルにない"
        elif [[ "${expected}" != "${actual}" ]]; then
          fail "README の動詞表: dots ${domain} ${verb} は テーブルでは ${expected}、README では ${actual}"
        fi
      done
    fi
    index=$((index + 1))
  done
  readme_domains="${readme_domains} ${domains}"
done <<< "${rows}"

for domain in $(printf '%s\n' "${matrix}" | cut -f1 | awk '!seen[$0]++'); do
  case " ${readme_domains} " in
    *" ${domain} "*) ;;
    *) fail "動詞テーブルのドメイン '${domain}' が README の動詞表にない" ;;
  esac
done

# ── 2. Windows 側のテーブル ───────────────────────────────────────────────────
ps1_specs="$(awk '
  /^\$verbSpecs = @\{/ { in_block = 1; next }
  in_block && /^\}/ { exit }
  in_block { print }
' "${PS1_FILE}")"

if [[ -z "${ps1_specs}" ]]; then
  fail "bin/windows/dots.ps1 に \$verbSpecs が見つからない"
fi

while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  domain="$(printf '%s' "${line}" | sed -n "s/^[[:space:]]*'\([a-z]*\)'[[:space:]]*=.*/\1/p")"
  spec="$(printf '%s' "${line}" | sed -n "s/^[^=]*=[[:space:]]*'\(.*\)'[[:space:]]*$/\1/p")"
  if [[ -z "${domain}" || -z "${spec}" ]]; then
    fail "bin/windows/dots.ps1 の \$verbSpecs を解釈できない: ${line}"
    continue
  fi
  expected="$(spec_of "${domain}")"
  if [[ "${expected}" != "${spec}" ]]; then
    fail "bin/windows/dots.ps1 の '${domain}' がテーブルと異なる: ps1='${spec}' unix='${expected}'"
  fi
done <<< "${ps1_specs}"

if (( errors > 0 )); then
  echo "dots の動詞テーブルの不整合が ${errors} 件ある。" >&2
  echo "正本は bin/unix/_dots-verbs.sh。README.md の動詞表と bin/windows/dots.ps1 を合わせること。" >&2
  exit 1
fi
echo "dots の動詞テーブル: README・Windows とも整合"
