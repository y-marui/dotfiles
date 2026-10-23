#!/usr/bin/env bash
# host-role.sh
# この端末の役割（work / other）を返す。他のスクリプトが source して使う。
#
# 役割は host/role（コミット対象外）に work か other と1語で書く。
#   work   作業PC。ghq/get の宣言を取得し、pipx の ghq: 指定を editable で入れる
#   other  サーバーなどそれ以外。何もしない
# host/role がなければ other として扱う（dots check は macOS でだけ未設定を警告する）。
# 環境変数 DOTS_HOST_ROLE が設定されていれば host/role より優先する（テスト・一時的な上書き用）。

# 標準出力に work / other / invalid / unset のいずれかを出す。
dots_host_role() {
  local dotfiles_dir="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local role="${DOTS_HOST_ROLE:-}" file="${dotfiles_dir}/host/role"

  if [[ -z "${role}" && -f "${file}" ]]; then
    role="$(sed -e 's/\r$//' -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "${file}" | grep -v '^$' | head -n 1 || true)"
  fi
  case "${role}" in
    work|other) printf '%s' "${role}" ;;
    '') printf 'unset' ;;
    *) printf 'invalid' ;;
  esac
}

# work のときだけ 0。unset / invalid / other は 1。
dots_host_is_work() {
  [[ "$(dots_host_role)" == work ]]
}
