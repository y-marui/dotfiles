#!/bin/bash
set -euo pipefail
# Claude Code PreToolUse hook
# stdin: JSON { "tool_input": { "command": "..." }, ... }
# コマンドを書き換えた場合だけ、hookSpecificOutput.updatedInput（tool_input全体）をstdoutへ出す。
# 書き換えない場合は何も出力せず、そのまま実行させる。
#
# 書き換えるのはシェルコマンドとして実行される行だけで、ヒアドキュメントの本文
# （cat > file <<'EOF' ... EOF のような、ファイルや標準入力へ渡すデータ）は書き換えない。
# 本文の行頭にある `git commit` 等まで書き換えると、書き出すファイルの中身が壊れるため。

# run-quiet が PATH に無い環境（Windows の Git Bash 等）で書き換えると、
# `run-quiet: command not found` でコマンドが失敗するため、何もせず素通しする。
if ! command -v run-quiet >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

if [ -z "$cmd" ]; then
  exit 0
fi

# 各行の先頭に C:（コマンド）または H:（ヒアドキュメント本文・終端行）を付ける。
# 同じ行の複数のヒアドキュメント（cat <<A <<B）は、出現順に本文が続くものとして扱う。
# here-string（<<<）はヒアドキュメントではないので除外する。
heredoc_re="<<(-?)[[:space:]]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)['\"]?"
marked=""
delims=()
strip_tabs=()
while IFS= read -r line || [ -n "$line" ]; do
  if [ "${#delims[@]}" -gt 0 ]; then
    end_line="$line"
    if [ "${strip_tabs[0]}" = "-" ]; then
      end_line="${line#"${line%%[!$'\t']*}"}"
    fi
    marked+="H:${line}"$'\n'
    if [ "$end_line" = "${delims[0]}" ]; then
      delims=("${delims[@]:1}")
      strip_tabs=("${strip_tabs[@]:1}")
    fi
    continue
  fi
  marked+="C:${line}"$'\n'
  probe="${line//<<</}"
  while [[ "$probe" =~ $heredoc_re ]]; do
    delims+=("${BASH_REMATCH[3]}")
    strip_tabs+=("${BASH_REMATCH[1]}")
    probe="${probe#*"${BASH_REMATCH[0]}"}"
  done
done <<< "$cmd"

SEP='(^|; *| *&& *| *\|\| *)'
new_cmd=$(printf '%s' "$marked" | sed -E \
  -e '/^C:/{' \
  -e 's/^C://' \
  -e "s/${SEP}(run-quiet )?git commit/\1run-quiet git commit/g" \
  -e "s/${SEP}(run-quiet )?make /\1run-quiet make /g" \
  -e "s/${SEP}(run-quiet )?swift (build|test|run)/\1run-quiet swift \3/g" \
  -e "s/${SEP}(run-quiet )?npm (test|run|install|ci|build)/\1run-quiet npm \3/g" \
  -e "s/${SEP}(run-quiet )?pre-commit run/\1run-quiet pre-commit run/g" \
  -e '}' \
  -e 's/^[CH]://' \
)
# 元の cmd と同じく末尾の改行は $(...) が取り除く

if [ "$new_cmd" != "$cmd" ]; then
  printf '%s' "$input" | jq --arg c "$new_cmd" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = $c)}}'
fi
