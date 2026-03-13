#!/usr/bin/env bash
set -euo pipefail
[ -z "${NTFY_TOPIC:-}" ] && exit 0
INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Stop"')
PROJECT=$(echo "$INPUT" | jq -r '.cwd // empty' | xargs basename 2>/dev/null || echo "unknown")
MSG=$(echo "$INPUT" | jq -r '.message // ""')
[ "$MSG" = "null" ] && MSG=""

case "$EVENT" in
  Stop)
    TITLE="Claude Code ($PROJECT)"
    BODY="${MSG:-タスク完了}"
    PRI="default"
    TAG="white_check_mark"
    ;;
  Notification)
    # 承認・入力待ちメッセージのみ通知（ホワイトリスト方式）
    echo "$MSG" | grep -qiE "waiting|wants to|would like to|permission|承認|許可" || exit 0
    TITLE="Claude Code ($PROJECT) – 承認待ち"
    BODY="${MSG:-入力が必要}"
    PRI="high"
    TAG="bell"
    ;;
  *)
    exit 0
    ;;
esac

curl -s \
  -H "Title: $TITLE" \
  -H "Priority: $PRI" \
  -H "Tags: $TAG" \
  -d "$BODY" \
  "${NTFY_URL:-https://ntfy.sh}/${NTFY_TOPIC}" > /dev/null 2>&1 || true
