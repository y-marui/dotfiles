#!/usr/bin/env bash
# dots check をバックグラウンド実行し、macOS通知を出す。
# 結果キャッシュ（check-summary/check-state/check-digest）自体は
# `dots check`本体（bin/unix/dots）が書き込む。ユーザーが手動で
# `dots check`を実行した場合も同じキャッシュが更新されるようにするため、
# ここでは書き込みを重複させず、実行前後の状態を比較して通知するだけに留める。

set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.local/bin/dotfiles:${HOME}/.pyenv/shims:${HOME}/.nodebrew/current/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG="${LANG:-ja_JP.UTF-8}"

CACHE_DIR="${DOTS_CHECK_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/dots}"
SUMMARY_FILE="${CACHE_DIR}/check-summary"
STATE_FILE="${CACHE_DIR}/check-state"
DIGEST_FILE="${CACHE_DIR}/check-digest"
DOTS_BIN="${DOTS_MONITOR_DOTS_BIN:-${HOME}/.local/bin/dotfiles/dots}"

mkdir -p "${CACHE_DIR}"
chmod 700 "${CACHE_DIR}"
umask 077

previous_state="$(sed -n '1p' "${STATE_FILE}" 2>/dev/null || true)"
previous_digest="$(sed -n '1p' "${DIGEST_FILE}" 2>/dev/null || true)"

if [[ ! -x "${DOTS_BIN}" ]]; then
  # dotsコマンド自体が見つからず dots check を起動できない場合だけ、
  # ここで直接キャッシュへ書き込む（通常経路のキャッシュ書き込みは
  # dots check 自身が行う）。
  state="error"
  summary="⚠ dots monitor: dotsコマンドが見つかりません: ${DOTS_BIN}"
  digest="$(printf '%s\n%s' "${state}" "${summary}" | shasum -a 256 | awk '{print $1}')"
  summary_tmp="$(mktemp "${SUMMARY_FILE}.XXXXXX")"
  printf '%s\n' "${summary}" > "${summary_tmp}"
  mv "${summary_tmp}" "${SUMMARY_FILE}"
  printf '%s\n' "${state}" > "${STATE_FILE}"
  printf '%s\n' "${digest}" > "${DIGEST_FILE}"
else
  "${DOTS_BIN}" check >/dev/null 2>&1 || true
fi

state="$(sed -n '1p' "${STATE_FILE}" 2>/dev/null || true)"
digest="$(sed -n '1p' "${DIGEST_FILE}" 2>/dev/null || true)"
summary="$(cat "${SUMMARY_FILE}" 2>/dev/null || true)"

_notify() {
  local title="$1" message="$2" with_popup="${3:-0}"
  [[ "${DOTS_MONITOR_DISABLE_NOTIFICATION:-0}" != 1 ]] || return 0
  [[ "$(uname -s)" == "Darwin" ]] || return 0

  # osascript の display notification はクリック時の送信元がScript Editorに固定され、
  # クリックすると空の新規スクリプトが開いてしまう。terminal-notifierがあれば
  # -executeでポップアップ表示スクリプトを起動し、それ以外の場合のみフォールバックする。
  if [[ "${with_popup}" == 1 ]] && command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "${title}" -message "${message}" \
      -execute "${HOME}/.local/bin/dots-check-monitor-popup" >/dev/null 2>&1 || true
  else
    /usr/bin/osascript - "${title}" "${message}" <<'APPLESCRIPT' >/dev/null
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
  fi
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
      _notify "dotfiles check: 要確認" "${first_line}  クリックで詳細を確認できます。" 1 || true
      ;;
  esac
fi

exit 0
