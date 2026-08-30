#!/usr/bin/env bash
# dots-check-monitorの通知クリック時に、terminal-notifierの-executeから呼ばれる。
# エラー内容をダイアログ表示し、コピー/閉じるを選ばせる。

set -euo pipefail

CACHE_DIR="${DOTS_MONITOR_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/dots}"
SUMMARY_FILE="${CACHE_DIR}/check-summary"

summary="$(cat "${SUMMARY_FILE}" 2>/dev/null || true)"
[[ -n "${summary}" ]] || summary="(詳細なし。dots check を実行してください)"

button="$(/usr/bin/osascript - "${summary}" <<'APPLESCRIPT'
on run argv
  set body to item 1 of argv
  display dialog body with title "dotfiles check: 要確認" buttons {"コピー", "閉じる"} default button "閉じる"
  return button returned of result
end run
APPLESCRIPT
)"

if [[ "${button}" == "コピー" ]]; then
  printf '%s' "${summary}" | pbcopy
fi
