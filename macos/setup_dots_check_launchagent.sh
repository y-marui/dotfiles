#!/usr/bin/env bash
# dots check の定期監視LaunchAgentを登録・解除する。

set -euo pipefail

ACTION="${1:-install}"
LABEL="com.y-marui.dotfiles-check"
DOMAIN="gui/$(id -u)"
SERVICE="${DOMAIN}/${LABEL}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '  SKIP    %s (macOS専用)\n' "${LABEL}"
  exit 0
fi

case "${ACTION}" in
  install)
    if [[ ! -f "${PLIST}" ]]; then
      printf 'error: LaunchAgent plistがありません: %s (先にmake linksを実行してください)\n' \
        "${PLIST}" >&2
      exit 1
    fi
    plutil -lint "${PLIST}" >/dev/null

    if ! launchctl print "${DOMAIN}" >/dev/null 2>&1; then
      printf '  SKIP    %s (GUIセッション外のため登録できません)\n' "${LABEL}"
      exit 0
    fi

    if launchctl print "${SERVICE}" >/dev/null 2>&1; then
      launchctl bootout "${SERVICE}"
    fi
    launchctl bootstrap "${DOMAIN}" "${PLIST}"
    launchctl enable "${SERVICE}"
    printf '  LOAD    %s (1時間ごと・ログイン時)\n' "${LABEL}"
    ;;
  uninstall)
    if launchctl print "${SERVICE}" >/dev/null 2>&1; then
      launchctl bootout "${SERVICE}"
      printf '  UNLOAD  %s\n' "${LABEL}"
    else
      printf '  SKIP    %s (未登録)\n' "${LABEL}"
    fi
    ;;
  *)
    printf 'usage: %s {install|uninstall}\n' "$0" >&2
    exit 2
    ;;
esac
