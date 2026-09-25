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
#                                         （宣言なし・ghq なし・想定外の失敗などのエラーは終了コード2）
#   keep-up-to-date.sh apply [--no-prune] [--dry-run]
#                                         宣言 → 実状態（完全一致。宣言外の true は --unset）。
#                                         --no-prune は宣言済みを true にするだけで --unset しない
#   keep-up-to-date.sh prune [--dry-run]  宣言にない true を --unset するだけ（true にはしない）
#   keep-up-to-date.sh sync [--dry-run] [--yes]
#                                         実状態 → 共通宣言（完全一致。取得済みのみ追加・削除）。
#                                         共通宣言から削除する場合は --yes が必要
#   keep-up-to-date.sh merge [--dry-run]  実状態 → 共通宣言（追加のみ。削除しない）
#   --dry-run は何も変更せず、実行した場合の変更予定だけを表示する
#   dots ghq {apply|diff|sync|merge|prune}
#
# 環境変数（テスト用の上書き）:
#   GHQ_ROOT               ghq root（ghq 自体も参照する）
#   DOTFILES_PRIVATE_DIR   dotfiles-private の場所（既定: <dotfiles>-private）

set -eEuo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-${DOTFILES_DIR}-private}"
DECL_FILE="${PRIVATE_DIR}/ghq/keep-up-to-date"
DECL_LOCAL_FILE="${DECL_FILE}.local"
CONFIG_KEY="local.keep-up-to-date"

export LC_ALL=C

# 想定外の失敗は、差分あり（終了コード1）と区別できるよう終了コード2にする。
trap 'exit 2' ERR

ACTION="${1:-}"
[[ -n "${ACTION}" ]] || { echo "usage: keep-up-to-date.sh {apply|diff|sync|merge|prune}" >&2; exit 2; }
shift
case "${ACTION}" in
  apply|diff|sync|merge|prune) ;;
  *) echo "error: unknown action: ${ACTION}" >&2; exit 2 ;;
esac
SUMMARY=false
NO_PRUNE=false
DRY_RUN=false
YES=false
while (( $# > 0 )); do
  case "$1" in
    --summary)
      [[ "${ACTION}" == diff ]] || { echo "error: --summary は diff でのみ使えます" >&2; exit 2; }
      SUMMARY=true
      ;;
    --no-prune)
      [[ "${ACTION}" == apply ]] || { echo "error: --no-prune は apply でのみ使えます" >&2; exit 2; }
      NO_PRUNE=true
      ;;
    --dry-run)
      [[ "${ACTION}" != diff ]] || { echo "error: --dry-run は diff では使えません" >&2; exit 2; }
      DRY_RUN=true
      ;;
    --yes)
      [[ "${ACTION}" == sync ]] || { echo "error: --yes は sync でのみ使えます" >&2; exit 2; }
      YES=true
      ;;
    *) echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# --summary（dots check 用）は、対象外の環境では何も出さずに正常終了する。
_unavailable() {
  [[ "${SUMMARY}" == true ]] && exit 0
  echo "error: $1" >&2
  exit 2
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

# 複数の ghq root が設定されていても、各リポジトリを所属する root からの相対パスにする。
ghq root --all > "${TMP}/roots"

# 取得済みリポジトリ: <キー>\t<パス>\t<相対パス>
ghq list -p | while IFS= read -r path; do
  rel="${path}"
  while IFS= read -r root; do
    if [[ "${path}" == "${root}"/* ]]; then
      rel="${path#"${root}"/}"
      break
    fi
  done < "${TMP}/roots"
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

HAS_DIFF=false

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
  HAS_DIFF=true
  if (( n_plus > 0 )); then
    echo "${CONFIG_KEY}=true だが宣言なし (+actual のみ):"
    _rels "${TMP}/plus" | sort -f | sed 's/^/  [+actual]  /'
    echo
  fi
  if (( n_minus > 0 )); then
    echo "宣言済みだが ${CONFIG_KEY} が true でない (-file のみ):"
    _rels "${TMP}/minus" | sort -f | sed 's/^/  [-file]  /'
  fi
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
  if [[ "${DRY_RUN}" == true ]]; then
    echo
    echo "[dry-run] 共通宣言は変更していません"
    return 0
  fi
  if (( n_remove > 0 )) && [[ "${YES}" == false ]]; then
    echo "error: 共通宣言から上記のエントリを削除します。実行するには --yes を付けてください" >&2
    echo "  （削除せず追加だけ行う場合は dots ghq merge）" >&2
    exit 2
  fi
  _rewrite "${TMP}/remove" "${TMP}/add"
  echo
  echo "keep-up-to-date ${ACTION}: +${n_add} added / -${n_remove} removed"
}

# apply: 宣言済みを true にし（minus）、宣言外の true を --unset する（plus）。
# prune: --unset だけ行う。--no-prune（apply）: true にするだけで --unset しない。
# --dry-run は git config を書き換えず、予定だけを表示する。
_apply() {
  local mode="$1" path rel n_set=0 n_unset=0 tag=""
  [[ "${DRY_RUN}" == false ]] || tag="[dry-run] "

  if [[ "${mode}" == apply ]]; then
    while IFS= read -r rel; do
      path="$(awk -F'\t' -v r="${rel}" '$3 == r { print $2; exit }' "${TMP}/fetched.tsv")"
      [[ "${DRY_RUN}" == true ]] || git -C "${path}" config --local --bool "${CONFIG_KEY}" true
      printf '%s[set]    %s\n' "${tag}" "${rel}"
      n_set=$((n_set + 1))
    done < <(_rels "${TMP}/minus")
  fi
  if [[ "${NO_PRUNE}" == true ]]; then
    if (( $(_count "${TMP}/plus") > 0 )); then
      echo "--no-prune: 宣言にない ${CONFIG_KEY}=true は解除しません（dots ghq prune で解除）:"
      _rels "${TMP}/plus" | sort -f | sed 's/^/  /'
    fi
  else
    while IFS= read -r rel; do
      path="$(awk -F'\t' -v r="${rel}" '$3 == r { print $2; exit }' "${TMP}/fetched.tsv")"
      [[ "${DRY_RUN}" == true ]] || git -C "${path}" config --local --unset "${CONFIG_KEY}"
      printf '%s[unset]  %s\n' "${tag}" "${rel}"
      n_unset=$((n_unset + 1))
    done < <(_rels "${TMP}/plus")
  fi

  if (( n_set == 0 && n_unset == 0 )); then
    if [[ "${mode}" == prune ]]; then
      echo "No change: 宣言にない ${CONFIG_KEY} はありません。"
    else
      echo "No change: 宣言はすでに各リポジトリへ適用済みです。"
    fi
    return 0
  fi
  echo
  echo "keep-up-to-date ${mode}: ${n_set} set / ${n_unset} unset"
  [[ "${DRY_RUN}" == false ]] || echo "[dry-run] 各リポジトリの ${CONFIG_KEY} は変更していません"
}

case "${ACTION}" in
  diff)  _diff; [[ "${HAS_DIFF}" == false ]] || exit 1 ;;
  apply) _apply apply ;;
  prune) _apply prune ;;
  sync)  _write_decl true ;;
  merge) _write_decl false ;;
esac
