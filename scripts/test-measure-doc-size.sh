#!/usr/bin/env bash
# scripts/measure-doc-size.py の回帰テスト。一時ディレクトリの小さな md だけを測るため、
# 実際の AI_CONTEXT.md やリポジトリには触れない。
set -euo pipefail

TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/measure-doc-size.py"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

check() { # name, expected, actual
  if [[ "$2" == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$2', got '$3'"
    FAILURES=$((FAILURES + 1))
  fi
}

field() { # file, key
  python3 "$TOOL" --path "$1" --json | python3 -c \
    "import json,sys; print(json.load(sys.stdin)[0]['$2'])"
}

# 全角は2桁、コードブロック・表・URL行は幅の対象外
{
  printf '%s\n' 'あいう'
  printf '%s\n' '~~~'
  printf '%.0sx' {1..150}; echo
  printf '%s\n' '~~~'
  printf '| %.0sy' {1..80}; echo
  printf 'https://example.com/'; printf '%.0sz' {1..150}; echo
  printf '%s\n' 'abc'
} > "$WORK/width.md"
check "width excludes exempt lines, counts fullwidth as 2" 6 "$(field "$WORK/width.md" width)"
check "line count" 7 "$(field "$WORK/width.md" lines)"

# 行数超過
printf 'a\n%.0s' {1..201} > "$WORK/long.md"
check "lines over guideline" "['lines']" "$(field "$WORK/long.md" over)"

# 幅超過
printf '%.0sa' {1..101} > "$WORK/wide.md"
check "width over guideline" "['width']" "$(field "$WORK/wide.md" over)"

# トークン: kind ごとの閾値(3,000 / 6,000)。日本語は1文字約1
python3 -c "print(('あ' * 50 + chr(10)) * 70, end='')" > "$WORK/tok.md"
check "tokens over for always" "['tokens']" "$(field "$WORK/tok.md" over)"
check "tokens ok for reference" "[]" \
  "$(python3 "$TOOL" --path "$WORK/tok.md" --kind reference --json |
    python3 -c "import json,sys; print(json.load(sys.stdin)[0]['over'])")"

# 超過しても終了コードは 0(強制しない)
python3 "$TOOL" --path "$WORK/long.md" > "$WORK/out.txt"
check "exit code 0 when exceeded" 0 "$?"
check "table marks exceeded" 1 "$(grep -c '201\*' "$WORK/out.txt")"

if ((FAILURES > 0)); then
  echo "$FAILURES failure(s)"
  exit 1
fi
echo "all passed"
