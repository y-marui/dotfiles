#!/usr/bin/env bash
# get.sh
# 作業PC（host/role が work の端末）で、宣言したリポジトリを ghq get で取得する。
# 未取得のものだけを取得し、取得済みのものは更新しない（更新は ghq-pull / ghq-update）。
#
# 宣言ファイル（ghq root からの相対パスを1行1件、# 以降はコメント）:
#   <private>/ghq/get        共通の宣言
#   <private>/ghq/get.local  この端末だけの追加分（コミット対象外）
# 宣言の集合は上記2ファイルの和集合。keep-up-to-date（更新対象）とは別の宣言。
#
# 使い方:
#   get.sh [--dry-run] [--force] [--summary]   dots ghq get
#   --dry-run  何も取得せず、取得予定だけを表示する
#   --force    host/role を無視して取得する（役割が work でない端末での一時的な実行用）
#   --summary  未取得の件数だけを1行で出す（dots check 用。未取得があれば終了コード1、役割が work でなければ何も出さない）
#
# 終了コード: 0 正常（役割が work でなく何もしなかった場合を含む）/ 1 一部の取得に失敗 / 2 使い方・環境のエラー
#
# 環境変数（テスト用の上書き）: GHQ_ROOT / DOTFILES_PRIVATE_DIR / DOTS_HOST_ROLE

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-${DOTFILES_DIR}-private}"
DECL_FILE="${PRIVATE_DIR}/ghq/get"
DECL_LOCAL_FILE="${DECL_FILE}.local"

# shellcheck source=../scripts/host-role.sh
source "${DOTFILES_DIR}/scripts/host-role.sh"

DRY_RUN=false
FORCE=false
SUMMARY=false
while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --summary) SUMMARY=true ;;
    *) echo "usage: get.sh [--dry-run] [--force] [--summary]" >&2; exit 2 ;;
  esac
  shift
done

role="$(dots_host_role)"
if [[ "${FORCE}" == false && "${role}" != work ]]; then
  [[ "${SUMMARY}" == true ]] || echo "skip: この端末の役割は work ではありません（${role}）。host/role に work と書くと取得します。"
  exit 0
fi

command -v ghq >/dev/null 2>&1 || { echo "error: 'ghq' が見つかりません。" >&2; exit 2; }
[[ -f "${DECL_FILE}" ]] || { echo "error: 宣言ファイルがありません: ${DECL_FILE}" >&2; exit 2; }

_entries() {
  [[ -f "$1" ]] || return 0
  sed -e 's/\r$//' -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#/*$##' "$1" | grep -v '^$' || true
}

# ghq list -p のうち、取得済みの相対パスを小文字で集める（複数 root にも対応）。
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
ghq root --all > "${TMP}/roots"
ghq list -p | while IFS= read -r path; do
  rel="${path}"
  while IFS= read -r root; do
    if [[ "${path}" == "${root}"/* ]]; then rel="${path#"${root}"/}"; break; fi
  done < "${TMP}/roots"
  printf '%s\n' "${rel}" | tr '[:upper:]' '[:lower:]'
done | sort -u > "${TMP}/fetched"

tag=""
[[ "${DRY_RUN}" == false ]] || tag="[dry-run] "

n_get=0
n_skip=0
n_fail=0
while IFS= read -r entry; do
  key="$(printf '%s' "${entry}" | tr '[:upper:]' '[:lower:]')"
  if grep -qxF -- "${key}" "${TMP}/fetched"; then
    n_skip=$((n_skip + 1))
    continue
  fi
  if [[ "${SUMMARY}" == true ]]; then
    n_get=$((n_get + 1))
  elif [[ "${DRY_RUN}" == true ]]; then
    printf '%s[get]    %s\n' "${tag}" "${entry}"
    n_get=$((n_get + 1))
  elif ghq get "${entry}"; then
    printf '[get]    %s\n' "${entry}"
    n_get=$((n_get + 1))
  else
    printf '[failed] %s（private の場合は gh auth login を確認）\n' "${entry}" >&2
    n_fail=$((n_fail + 1))
  fi
done < <({ _entries "${DECL_FILE}"; _entries "${DECL_LOCAL_FILE}"; } | awk '!seen[tolower($0)]++')

if [[ "${SUMMARY}" == true ]]; then
  (( n_get == 0 )) || { printf -- '-%s 未取得\n' "${n_get}"; exit 1; }
  exit 0
fi

echo "ghq get: ${n_get} get / ${n_skip} already fetched / ${n_fail} failed"
(( n_fail == 0 )) || exit 1
