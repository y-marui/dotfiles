#!/usr/bin/env bash
# dots check をバックグラウンド実行し、結果キャッシュとmacOS通知を更新する。

set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.local/bin/dotfiles:${HOME}/.nodebrew/current/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG="${LANG:-ja_JP.UTF-8}"

CACHE_DIR="${DOTS_MONITOR_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/dots}"
SUMMARY_FILE="${CACHE_DIR}/check-summary"
STATE_FILE="${CACHE_DIR}/check-state"
DIGEST_FILE="${CACHE_DIR}/check-digest"
DOTS_BIN="${DOTS_MONITOR_DOTS_BIN:-${HOME}/.local/bin/dotfiles/dots}"

mkdir -p "${CACHE_DIR}"
chmod 700 "${CACHE_DIR}"
umask 077

if [[ ! -x "${DOTS_BIN}" ]]; then
  output="⚠ dots monitor: dotsコマンドが見つかりません: ${DOTS_BIN}"
  check_status=127
else
  set +e
  output="$("${DOTS_BIN}" check 2>&1)"
  check_status=$?
  set -e
fi

if [[ "${check_status}" -eq 0 ]]; then
  state="clean"
  summary=""
elif [[ -n "${output}" ]]; then
  state="warning"
  summary="${output}"
else
  state="error"
  summary="⚠ dots monitor: dots check failed (exit ${check_status})"
fi

previous_state="$(sed -n '1p' "${STATE_FILE}" 2>/dev/null || true)"
previous_digest="$(sed -n '1p' "${DIGEST_FILE}" 2>/dev/null || true)"
digest="$(printf '%s\n%s' "${state}" "${summary}" | shasum -a 256 | awk '{print $1}')"

summary_tmp="$(mktemp "${SUMMARY_FILE}.XXXXXX")"
if [[ -n "${summary}" ]]; then
  printf '%s\n' "${summary}" > "${summary_tmp}"
else
  : > "${summary_tmp}"
fi
mv "${summary_tmp}" "${SUMMARY_FILE}"
printf '%s\n' "${state}" > "${STATE_FILE}"
printf '%s\n' "${digest}" > "${DIGEST_FILE}"

_notify() {
  local title="$1" message="$2"
  [[ "${DOTS_MONITOR_DISABLE_NOTIFICATION:-0}" != 1 ]] || return 0
  [[ "$(uname -s)" == "Darwin" ]] || return 0

  /usr/bin/osascript - "${title}" "${message}" <<'APPLESCRIPT' >/dev/null
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

if [[ "${digest}" != "${previous_digest}" ]]; then
  case "${state}" in
    clean)
      if [[ -n "${previous_state}" && "${previous_state}" != clean ]]; then
        _notify "dotfiles check" "すべての警告が解消しました。" || true
      fi
      ;;
    warning|error)
      first_line="$(printf '%s\n' "${summary}" | sed -n '1p')"
      _notify "dotfiles check: 要確認" "${first_line}  dots check で確認してください。" || true
      ;;
  esac
fi

exit 0
