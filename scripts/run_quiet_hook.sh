#!/bin/bash
set -euo pipefail
# Claude Code PreToolUse hook
# stdin: JSON { "tool_input": { "command": "..." }, ... }
# コマンドを書き換えた場合だけ、hookSpecificOutput.updatedInput（tool_input全体）をstdoutへ出す。
# 書き換えない場合は何も出力せず、そのまま実行させる。

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

if [ -z "$cmd" ]; then
  exit 0
fi

SEP='(^|; *| *&& *| *\|\| *)'
new_cmd=$(printf '%s' "$cmd" | sed -E \
  -e "s/${SEP}(run-quiet )?git commit/\1run-quiet git commit/g" \
  -e "s/${SEP}(run-quiet )?make /\1run-quiet make /g" \
  -e "s/${SEP}(run-quiet )?swift (build|test|run)/\1run-quiet swift \3/g" \
  -e "s/${SEP}(run-quiet )?npm (test|run|install|ci|build)/\1run-quiet npm \3/g" \
  -e "s/${SEP}(run-quiet )?pre-commit run/\1run-quiet pre-commit run/g" \
)

if [ "$new_cmd" != "$cmd" ]; then
  printf '%s' "$input" | jq --arg c "$new_cmd" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = $c)}}'
fi
