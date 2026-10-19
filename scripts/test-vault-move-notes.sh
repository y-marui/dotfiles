#!/usr/bin/env bash
# scripts/vault-move-notes.py の回帰テスト。一時ディレクトリのフィクスチャvaultだけを使い、
# 実際のVaultには触れない。
# shellcheck disable=SC2016 # バッククォートはフィクスチャ/検索の文字列そのもの
set -euo pipefail

TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vault-move-notes.py"
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

V="$WORK/vault"

make_vault() {
  rm -rf "$V"
  mkdir -p "$V/knowledge/proposals" "$V/projects" "$V/records" "$V/private" "$V/.obsidian" "$V/system/bases"
  git -C "$V" init -q
  git -C "$V" config user.email t@example.com
  git -C "$V" config user.name t
  git -C "$V" config hooks.skip-policy-check true
  printf '%s\n' '---' 'status: considering' '---' 'body [[other]]' > "$V/knowledge/proposals/idea.md"
  printf '%s\n' 'other' > "$V/knowledge/other.md"
  {
    printf '%s\n' '---' 'sources:' '  - "[[knowledge/proposals/idea]]"' 'project: "[[knowledge/proposals/idea.md|x]]"' '---'
    printf '%s\n' 'plain [[knowledge/proposals/idea]] and [[knowledge/proposals/idea|alias]]'
    printf '%s\n' 'head [[knowledge/proposals/idea#Heading]] block [[knowledge/proposals/idea#^abc]]'
    printf '%s\n' 'embed ![[knowledge/proposals/idea]] short [[idea]] same [[other]]'
    printf '%s\n' '| t |' '| [[knowledge/proposals/idea\|tbl]] |'
    printf '%s\n' 'inline `[[knowledge/proposals/idea]]` code'
    printf '%s\n' '```' '[[knowledge/proposals/idea]]' '```'
    printf '%s\n' 'broken [[missing-note]]'
  } > "$V/records/rec.md"
  printf '%s\n' '[[knowledge/proposals/idea]] secret' > "$V/private/p.md"
  printf '%s\n' '{"path":"knowledge/proposals/idea"}' > "$V/.obsidian/x.json"
  printf '%s\n' 'filters: knowledge/proposals/idea' > "$V/system/bases/a.base"
  git -C "$V" add -A
  git -C "$V" commit -q -m init
}

snapshot() { (cd "$V" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 shasum | shasum); }

# dry-run: 何も書かず、一覧と警告を出す
make_vault
before="$(snapshot)"
python3 "$TOOL" --vault "$V" --dry-run knowledge/proposals/idea.md projects/idea/idea-proposal.md \
  > "$WORK/out.txt" 2> "$WORK/err.txt"
check "dry-run writes nothing" "$before" "$(snapshot)"
check "dry-run lists changed file" 1 "$(grep -c 'records/rec.md: 9' "$WORK/out.txt")"
check "dry-run warns about .base" 1 "$(grep -c 'a.base' "$WORK/err.txt")"
check "dry-run warns about .obsidian" 1 "$(grep -c 'x.json' "$WORK/err.txt")"
check "dry-run warns about code" 2 "$(grep -c 'link in code' "$WORK/err.txt")"

# 実行: Record本文・frontmatterのリンク書き換え
python3 "$TOOL" --vault "$V" knowledge/proposals/idea.md projects/idea/idea-proposal.md > /dev/null 2>&1
rec="$V/records/rec.md"
check "file moved" yes "$([[ -f $V/projects/idea/idea-proposal.md && ! -e $V/knowledge/proposals/idea.md ]] && echo yes || echo no)"
check "git sees rename" 1 "$(git -C "$V" status --short | grep -c '^R')"
check "frontmatter list" 1 "$(grep -c '  - "\[\[projects/idea/idea-proposal\]\]"' "$rec")"
check "frontmatter keeps .md and alias" 1 "$(grep -c 'project: "\[\[projects/idea/idea-proposal.md|x\]\]"' "$rec")"
check "path and alias" 1 "$(grep -c 'plain \[\[projects/idea/idea-proposal\]\] and \[\[projects/idea/idea-proposal|alias\]\]' "$rec")"
check "heading and block" 1 "$(grep -c 'head \[\[projects/idea/idea-proposal#Heading\]\] block \[\[projects/idea/idea-proposal#^abc\]\]' "$rec")"
check "embed" 1 "$(grep -c 'embed !\[\[projects/idea/idea-proposal\]\]' "$rec")"
check "name-only rewritten on rename" 1 "$(grep -c 'short \[\[idea-proposal\]\] same \[\[other\]\]' "$rec")"
check "table escaped pipe" 1 "$(grep -c '| \[\[projects/idea/idea-proposal\\|tbl\]\] |' "$rec")"
check "inline code untouched" 1 "$(grep -c 'inline `\[\[knowledge/proposals/idea\]\]` code' "$rec")"
check "fence untouched" 1 "$(grep -c '^\[\[knowledge/proposals/idea\]\]$' "$rec")"
check "broken link kept" 1 "$(grep -c 'broken \[\[missing-note\]\]' "$rec")"
check "private untouched" 1 "$(grep -c '\[\[knowledge/proposals/idea\]\] secret' "$V/private/p.md")"
check "other link in moved file untouched" 1 "$(grep -c 'body \[\[other\]\]' "$V/projects/idea/idea-proposal.md")"

# 名前のみのリンクは、名前が変わらず一意なら書き換えない
make_vault
python3 "$TOOL" --vault "$V" knowledge/proposals/idea.md knowledge/idea.md > /dev/null 2>&1
check "name-only unchanged when basename same" 1 "$(grep -c 'short \[\[idea\]\]' "$V/records/rec.md")"
check "path link updated" 1 "$(grep -c 'plain \[\[knowledge/idea\]\]' "$V/records/rec.md")"

# --include-private でprivateも対象
make_vault
python3 "$TOOL" --vault "$V" --include-private knowledge/proposals/idea.md knowledge/idea.md > /dev/null 2>&1
check "include-private rewrites private" 1 "$(grep -c '\[\[knowledge/idea\]\] secret' "$V/private/p.md")"

# 移動先が既存なら失敗し、何も変えない
make_vault
before="$(snapshot)"
rc=0
python3 "$TOOL" --vault "$V" knowledge/proposals/idea.md knowledge/other.md > /dev/null 2>&1 || rc=$?
check "existing destination fails" 1 "$rc"
check "existing destination leaves vault intact" "$before" "$(snapshot)"

# 検証失敗(注入)なら書き込まずに非0
make_vault
before="$(snapshot)"
rc=0
VAULT_MOVE_NOTES_TEST_FAIL=verify python3 "$TOOL" --vault "$V" knowledge/proposals/idea.md knowledge/idea.md > /dev/null 2>&1 || rc=$?
check "verification failure exits non-zero" 1 "$rc"
check "verification failure writes nothing" "$before" "$(snapshot)"

# 書き込み途中の失敗はロールバックされる(移動・内容・作成ディレクトリ)
make_vault
before="$(snapshot)"
status_before="$(git -C "$V" status --short)"
rc=0
VAULT_MOVE_NOTES_TEST_FAIL=apply python3 "$TOOL" --vault "$V" knowledge/proposals/idea.md projects/idea/idea-proposal.md > /dev/null 2>&1 || rc=$?
check "apply failure exits non-zero" 1 "$rc"
check "apply failure restores files" "$before" "$(snapshot)"
check "apply failure restores git state" "$status_before" "$(git -C "$V" status --short)"
check "apply failure removes created dir" no "$([[ -d $V/projects/idea ]] && echo yes || echo no)"

if ((FAILURES > 0)); then
  echo "$FAILURES failure(s)"
  exit 1
fi
echo "all passed"
