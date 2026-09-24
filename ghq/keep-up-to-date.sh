#!/usr/bin/env bash
# keep-up-to-date.sh
# ghq-update の更新対象（各リポジトリの local.keep-up-to-date）を、
# dotfiles-private の宣言ファイルと突き合わせて管理する。
#
# 宣言ファイル（ghq root からの相対パスを1行1件、# 以降はコメント）:
#   <private>/ghq/keep-up-to-date        共通の宣言（sync / merge の書き込み先）
#   <private>/ghq/keep-up-to-date.local  この端末だけの追加分（手編集専用・追加のみ）
# 宣言の集合は上記2ファイルの和集合。パスの大文字小文字は区別しない。
# ghq root に取得されていないリポジトリは、宣言にあっても全動詞で無視する。
#
# 使い方:
#   keep-up-to-date.sh diff [--summary]   宣言と実状態の差分を表示（差分があれば終了コード1）
#   keep-up-to-date.sh apply              宣言 → 実状態（完全一致。宣言外の true は --unset）
#   keep-up-to-date.sh sync               実状態 → 共通宣言（完全一致。取得済みのみ追加・削除）
#   keep-up-to-date.sh merge              実状態 → 共通宣言（追加のみ。削除しない）
#   dots ghq {apply|diff|sync|merge}
#
# 環境変数（テスト用の上書き）:
#   GHQ_ROOT               ghq root（ghq 自体も参照する）
#   DOTFILES_PRIVATE_DIR   dotfiles-private の場所（既定: <dotfiles>-private）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-${DOTFILES_DIR}-private}"
DECL_FILE="${PRIVATE_DIR}/ghq/keep-up-to-date"
DECL_LOCAL_FILE="${DECL_FILE}.local"
CONFIG_KEY="local.keep-up-to-date"

export LC_ALL=C

ACTION="${1:-}"
[[ -n "${ACTION}" ]] || { echo "usage: keep-up-to-date.sh {apply|diff|sync|merge}" >&2; exit 1; }
shift
SUMMARY=false
while (( $# > 0 )); do
  case "$1" in
    --summary)
      [[ "${ACTION}" == diff ]] || { echo "error: --summary は diff でのみ使えます" >&2; exit 1; }
      SUMMARY=true
      shift
      ;;
    *) echo "error: unknown option: $1" >&2; exit 1 ;;
  esac
done
case "${ACTION}" in
  apply|diff|sync|merge) ;;
  *) echo "error: unknown action: ${ACTION}" >&2; exit 1 ;;
esac

# --summary（dots check 用）は、対象外の環境では何も出さずに正常終了する。
_unavailable() {
  [[ "${SUMMARY}" == true ]] && exit 0
  echo "error: $1" >&2
  exit 1
}

command -v ghq >/dev/null 2>&1 || _unavailable "'ghq' が見つかりません。"
[[ -f "${DECL_FILE}" ]] || _unavailable "宣言ファイルがありません: ${DECL_FILE}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# 宣言ファイルの各行を比較用のキー（コメント・空白・末尾スラッシュを除去し小文字化）へ。
_keys() {
  [[ -f "$1" ]] || return 0
  sed -e 's/\r$//' -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
      -e 's#/*$##' "$1" | grep -v '^$' | tr '[:upper:]' '[:lower:]' | sort -u || true
}

ghq_root="$(ghq root)"

# 取得済みリポジトリ: <キー>\t<パス>\t<相対パス>
ghq list -p | while IFS= read -r path; do
  rel="${path#"${ghq_root}"/}"
  printf '%s\t%s\t%s\n' "$(printf '%s' "${rel}" | tr '[:upper:]' '[:lower:]')" "${path}" "${rel}"
done | sort -t $'\t' -k1,1 > "${TMP}/fetched.tsv"
cut -f1 "${TMP}/fetched.tsv" | sort -u > "${TMP}/fetched"

# 実状態が true のもの（取得済みのみ）
: > "${TMP}/true.unsorted"
while IFS=$'\t' read -r key path _rel; do
  value="$(git -C "${path}" config --local --bool --get "${CONFIG_KEY}" 2>/dev/null)" || value=''
  [[ "${value}" == true ]] && printf '%s\n' "${key}" >> "${TMP}/true.unsorted"
done < "${TMP}/fetched.tsv"
sort -u "${TMP}/true.unsorted" > "${TMP}/true"

_keys "${DECL_FILE}" > "${TMP}/main"
_keys "${DECL_LOCAL_FILE}" > "${TMP}/local"
sort -u "${TMP}/main" "${TMP}/local" > "${TMP}/declared"

# 宣言なし: 実状態は true だが、共通・端末固有どちらの宣言にもない
comm -23 "${TMP}/true" "${TMP}/declared" > "${TMP}/plus"
# 未適用: 宣言済みで取得済みだが true でない
comm -12 "${TMP}/declared" "${TMP}/fetched" | comm -23 - "${TMP}/true" > "${TMP}/minus"
# sync で共通宣言から外す: 共通宣言にあり、取得済みで true でない
comm -12 "${TMP}/main" "${TMP}/fetched" | comm -23 - "${TMP}/true" > "${TMP}/main_stale"

# キーの一覧を、元の綴りの相対パスへ戻す。
_rels() {
  local key
  while IFS= read -r key; do
    awk -F'\t' -v k="${key}" '$1 == k { print $3; exit }' "${TMP}/fetched.tsv"
  done < "$1"
}

_count() { grep -c . "$1" || true; }

_diff() {
  local n_plus n_minus
  n_plus="$(_count "${TMP}/plus")"
  n_minus="$(_count "${TMP}/minus")"

  if [[ "${SUMMARY}" == true ]]; then
    if (( n_plus > 0 || n_minus > 0 )); then
      printf '+%s 宣言なし / -%s 未適用\n' "${n_plus}" "${n_minus}"
      exit 1
    fi
    exit 0
  fi

  if (( n_plus == 0 && n_minus == 0 )); then
    echo "No diff: 宣言と各リポジトリの ${CONFIG_KEY} は一致しています。"
    return 0
  fi
  if (( n_plus > 0 )); then
    echo "${CONFIG_KEY}=true だが宣言なし (+actual のみ):"
    _rels "${TMP}/plus" | sort -f | sed 's/^/  [+actual]  /'
    echo
  fi
  if (( n_minus > 0 )); then
    echo "宣言済みだが ${CONFIG_KEY} が true でない (-file のみ):"
    _rels "${TMP}/minus" | sort -f | sed 's/^/  [-file]  /'
  fi
  return 1
}

# 共通宣言ファイルを書き戻す。コメント・空行は先頭にまとめ、エントリは重複を除いて
# 大文字小文字を無視してソートする。引数: 削除キー一覧 / 追加する相対パス一覧
_rewrite() {
  local remove_file="$1" add_file="$2" out="${TMP}/decl.new"
  {
    grep -E '^[[:space:]]*(#|$)' "${DECL_FILE}" || true
    {
      awk -v rmfile="${remove_file}" '
        BEGIN { while ((getline line < rmfile) > 0) rm[line] = 1 }
        /^[[:space:]]*(#|$)/ { next }
        {
          key = $0
          sub(/\r$/, "", key); sub(/#.*$/, "", key)
          sub(/^[[:space:]]+/, "", key); sub(/[[:space:]]+$/, "", key)
          sub(/\/+$/, "", key)
          key = tolower(key)
          if (key in rm || key in seen) next
          seen[key] = 1
          print
        }' "${DECL_FILE}"
      cat "${add_file}"
    } | grep -v '^$' | sort -f
  } > "${out}"
  cat "${out}" > "${DECL_FILE}"
}

# sync / merge の共通処理: 共通宣言へ追加（plus）し、必要なら外す（main_stale）。
_write_decl() {
  local do_remove="$1" n_add n_remove
  _rels "${TMP}/plus" > "${TMP}/add"
  if [[ "${do_remove}" == true ]]; then
    cp "${TMP}/main_stale" "${TMP}/remove"
  else
    : > "${TMP}/remove"
  fi
  n_add="$(_count "${TMP}/add")"
  n_remove="$(_count "${TMP}/remove")"

  if (( n_add > 0 )); then sed 's/^/[add]    /' "${TMP}/add"; fi
  if (( n_remove > 0 )); then _rels "${TMP}/remove" | sed 's/^/[remove] /'; fi
  if (( n_add == 0 && n_remove == 0 )); then
    echo "No change: 共通宣言はすでに実状態と整合しています。"
    return 0
  fi
  _rewrite "${TMP}/remove" "${TMP}/add"
  echo
  echo "keep-up-to-date ${ACTION}: +${n_add} added / -${n_remove} removed"
}

_apply() {
  local path rel n_set=0 n_unset=0
  while IFS= read -r rel; do
    path="$(awk -F'\t' -v r="${rel}" '$3 == r { print $2; exit }' "${TMP}/fetched.tsv")"
    git -C "${path}" config --local --bool "${CONFIG_KEY}" true
    printf '[set]    %s\n' "${rel}"
    n_set=$((n_set + 1))
  done < <(_rels "${TMP}/minus")
  while IFS= read -r rel; do
    path="$(awk -F'\t' -v r="${rel}" '$3 == r { print $2; exit }' "${TMP}/fetched.tsv")"
    git -C "${path}" config --local --unset "${CONFIG_KEY}"
    printf '[unset]  %s\n' "${rel}"
    n_unset=$((n_unset + 1))
  done < <(_rels "${TMP}/plus")

  if (( n_set == 0 && n_unset == 0 )); then
    echo "No change: 宣言はすでに各リポジトリへ適用済みです。"
    return 0
  fi
  echo
  echo "keep-up-to-date apply: ${n_set} set / ${n_unset} unset"
}

case "${ACTION}" in
  diff)  _diff ;;
  apply) _apply ;;
  sync)  _write_decl true ;;
  merge) _write_decl false ;;
esac
