#!/usr/bin/env bash
# scripts/run_quiet_hook.sh の回帰テスト。PreToolUse hook へ渡す JSON を作って実行し、
# 書き換えの有無と、ヒアドキュメント本文が書き換えられないことを検証する。
# 外部への影響はない（jq が必要）。
set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_quiet_hook.sh"
FAILURES=0

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq が見つかりません" >&2
  exit 0
fi

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}

# run_hook COMMAND: hook の標準出力（書き換え後の command。書き換えなしなら空）を OUT に入れる
run_hook() {
  OUT="$(jq -n --arg c "$1" '{tool_input: {command: $c}}' | "${HOOK_BASH:-bash}" "$HOOK" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
}
unchanged() { [[ -z "$OUT" ]]; }
equals() { [[ "$OUT" == "$1" ]]; }

nl=$'\n'

echo "== plain commands =="
run_hook 'git commit -m x'
check "git commit is wrapped" equals 'run-quiet git commit -m x'
run_hook 'cd repo && git commit -am y'
check "after && is wrapped" equals 'cd repo && run-quiet git commit -am y'
run_hook 'git add . ; npm run build'
check "after ; is wrapped" equals 'git add . ; run-quiet npm run build'
run_hook 'run-quiet git commit -m x'
check "already wrapped is left alone" unchanged
run_hook 'git status'
check "unrelated command is left alone" unchanged
run_hook ''
check "empty command is left alone" unchanged

echo "== heredoc bodies are not rewritten =="
body="cat > f.txt <<'EOF'${nl}git commit -q -m body${nl}npm run build${nl}make all${nl}EOF"
run_hook "$body"
check "heredoc-only command is left alone" unchanged
run_hook "${body}${nl}git commit -m after"
check "command after the heredoc is wrapped, body is not" equals "${body}${nl}run-quiet git commit -m after"
run_hook "git commit -m before${nl}${body}"
check "command before the heredoc is wrapped, body is not" equals "run-quiet git commit -m before${nl}${body}"
run_hook "python3 - <<\"PY\"${nl}s = 'npm run build'${nl}git commit -m inner${nl}PY"
check "double-quoted delimiter" unchanged
run_hook "cat <<EOF${nl}git commit -m unquoted${nl}EOF"
check "unquoted delimiter" unchanged
run_hook "cat <<-EOF${nl}"$'\t'"git commit -m tabbed${nl}"$'\t'"EOF${nl}git commit -m after"
check "<<- with tab-indented terminator" equals "cat <<-EOF${nl}"$'\t'"git commit -m tabbed${nl}"$'\t'"EOF${nl}run-quiet git commit -m after"
run_hook "cat <<A <<B${nl}git commit -m a${nl}A${nl}npm run b${nl}B${nl}make x"
check "two heredocs on one line" equals "cat <<A <<B${nl}git commit -m a${nl}A${nl}npm run b${nl}B${nl}run-quiet make x"

echo "== here-strings and look-alikes =="
run_hook "cat <<< \"x\"${nl}git commit -m after"
check "here-string does not start a heredoc" equals "cat <<< \"x\"${nl}run-quiet git commit -m after"
run_hook "cat <<EOF${nl}body${nl}EOFX${nl}git commit -m still-body${nl}EOF"
check "terminator must match exactly" unchanged

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All run_quiet_hook regression checks passed."
else
  echo "$FAILURES run_quiet_hook regression check(s) failed." >&2
  exit 1
fi
