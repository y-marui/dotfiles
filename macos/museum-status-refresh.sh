#!/usr/bin/env bash
# 美術展タスクのステータス絵文字更新・並べ替えを非対話（AIを使わず）で実行する。

set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.local/bin/dotfiles:${HOME}/.nodebrew/current/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG="${LANG:-ja_JP.UTF-8}"

SCRIPT="${HOME}/.claude/skills/format-glance-task-museum-events/scripts/museum_events.py"

if [[ ! -f "${SCRIPT}" ]]; then
  echo "error: museum_events.py が見つかりません: ${SCRIPT} (先にmake linksを実行してください)" >&2
  exit 1
fi

exec python3 "${SCRIPT}" refresh --apply
