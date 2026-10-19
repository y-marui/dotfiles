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
printf '%.0sa' {1..201} > "$WORK/wide.md"
check "width over guideline" "['width']" "$(field "$WORK/wide.md" over)"

# 幅は文末(。！？!? と後ろに空白が続く .)で切った断片の最大値
python3 -c "print('あ' * 60 + '。' + 'い' * 60 + '。' + 'x. ' + 'y' * 150)" > "$WORK/sent.md"
check "width is per sentence fragment" 150 "$(field "$WORK/sent.md" width)"
printf '%s\n' 'v1.2.3' > "$WORK/dots.md"
check "dot without trailing space does not split" 6 "$(field "$WORK/dots.md" width)"

# frontmatter は行数・トークン・幅の対象外
{ printf -- '---\ndescription: x\n---\n'; printf 'a\n%.0s' {1..3}; } > "$WORK/fm.md"
check "frontmatter excluded from lines" 3 "$(field "$WORK/fm.md" lines)"

# --inventory: .doc-lint.toml の対象範囲・private/** は件数のみ
INV="$WORK/inv"
mkdir -p "$INV/repo/docs/dev-charter" "$INV/obsidian-vault/private/records" "$INV/obsidian-vault/private/x" "$INV/obsidian-vault/notes"
git -C "$INV/repo" init -q
git -C "$INV/obsidian-vault" init -q
printf -- '---\ndescription: ok\n---\nbody\n' > "$INV/repo/AGENTS.md"
printf 'no fm\n' > "$INV/repo/docs/a.md"
printf 'x\n' > "$INV/repo/docs/dev-charter/v.md"
printf 'x\n' > "$INV/repo/README.md"
printf 'scope = "all"\n' > "$INV/obsidian-vault/.doc-lint.toml"
printf 'x\n' > "$INV/obsidian-vault/notes/n.md"
printf 'secret\n' > "$INV/obsidian-vault/private/x/secret-title.md"
printf 'secret\n' > "$INV/obsidian-vault/private/records/r.md"
git -C "$INV/repo" add -A
git -C "$INV/obsidian-vault" add -A
python3 "$TOOL" --inventory --root "$INV/repo" "$INV/obsidian-vault" --json > "$WORK/inv.json"
q() { python3 -c "import json,sys; d=json.load(sys.stdin); $1" < "$WORK/inv.json"; }
check "inventory default scope files" "AGENTS.md README.md docs/a.md" \
  "$(q "print(' '.join(sorted(f['path'] for f in d['files'] if f['repo']=='repo')))")"
check "inventory excludes private by default" "notes/n.md" \
  "$(q "print(' '.join(f['path'] for f in d['files'] if f['repo']=='obsidian-vault'))")"
python3 "$TOOL" --inventory --include-private-counts --root "$INV/repo" "$INV/obsidian-vault" --json > "$WORK/inv.json"
check "private counted only (records excluded)" 1 \
  "$(q "print([r for r in d['repos'] if r['repo']=='obsidian-vault'][0]['private']['files'])")"
check "private paths never listed" 0 "$(grep -c 'secret-title' "$WORK/inv.json" || true)"
python3 "$TOOL" --inventory --root "$INV/repo" > "$WORK/inv.txt"
check "inventory table lists flagged file" 1 "$(grep -c 'repo/docs/a.md' "$WORK/inv.txt")"

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

# 別種のフェンスは閉じない(``` の中の ~~~ は本文扱いで、閉じ ``` までが対象外)
{
  printf '%s\n' '```'
  printf '%s\n' '~~~'
  printf '%.0sx' {1..150}; echo
  printf '%s\n' '```'
  printf '%s\n' 'abc'
} > "$WORK/fence.md"
check "fence closes only on matching marker" 3 "$(field "$WORK/fence.md" width)"

# --kind reference の超過もフッターに数える
printf '%s\n' 'x' > "$WORK/small.md"
python3 -c "print(('あ' * 50 + chr(10)) * 130, end='')" > "$WORK/ref.md"
python3 "$TOOL" --path "$WORK/ref.md" --kind reference > "$WORK/ref.txt"
check "reference footer counts exceeded" 1 "$(grep -c '1 over guideline' "$WORK/ref.txt")"

if ((FAILURES > 0)); then
  echo "$FAILURES failure(s)"
  exit 1
fi
echo "all passed"
