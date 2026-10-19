#!/usr/bin/env bash
# scripts/doc-lint.py と git/hooks の doc-lint 連携の回帰テスト。
# 一時ディレクトリのリポジトリとログだけを使い、実リポジトリや ~/.local/state には触れない。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/scripts/doc-lint.py"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT
export DOC_LINT_LOG="$WORK/state/deviations.log"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

check() { # name, expected, actual
  if [[ "$2" == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$2', got '$3'"
    FAILURES=$((FAILURES + 1))
  fi
}

REPO="$WORK/myrepo"
mkdir -p "$REPO/docs/dev-charter" "$REPO/private" "$REPO/sub"
git -C "$REPO" init -q
cd "$REPO"
python3 -c "print('line\n' * 250, end='')" > big.md
printf -- '---\ndescription: ok\n---\nbody\n' > good.md
printf 'plain\n' > docs/nofm.md
printf -- '---\ndescription: |\n  multi\n---\nx\n' > docs/multi.md
printf 'x\n' > README.md
printf 'x\n' > sub/out-of-scope.md
python3 -c "print('line\n' * 250, end='')" > docs/dev-charter/vendored.md
python3 -c "print('line\n' * 250, end='')" > private/secret-title.md
git add -A

err="$(python3 "$TOOL" 2>&1 >/dev/null)"; rc=$?
check "exit code 0 with warnings" 0 "$rc"
check "header" 1 "$(grep -c 'doc-lint (warn only): 3 file' <<<"$err")"
check "lines warning" 1 "$(grep -c 'big.md: lines 250>200' <<<"$err")"
check "frontmatter warnings" 3 "$(grep -cE 'frontmatter (no-frontmatter|multiline-description)' <<<"$err")"
check "good/README/vendored/sub not reported" 0 "$(grep -cE 'good.md|README|vendored|out-of-scope' <<<"$err")"
check "log rows" 4 "$(wc -l < "$DOC_LINT_LOG" | tr -d ' ')"
check "log has 6 TSV columns" 6 "$(head -1 "$DOC_LINT_LOG" | awk -F'\t' '{print NF}')"
check "log repo name" myrepo "$(head -1 "$DOC_LINT_LOG" | cut -f2)"

# 未ステージのファイルは対象外
: >| "$DOC_LINT_LOG"
printf 'unstaged\n' > docs/unstaged.md
err="$(python3 "$TOOL" 2>&1 >/dev/null)"
check "unstaged ignored" 0 "$(grep -c unstaged <<<"$err")"

# .doc-lint.toml: scope=all + exempt。private/ のパスは表示・記録しない
cat > .doc-lint.toml <<'TOML'
scope = "all"
exempt_all = ["docs/dev-charter/**", "docs/multi.md"]
exempt_size = ["big.md"]
exempt_frontmatter = ["docs/nofm.md"]
TOML
git add -A
: >| "$DOC_LINT_LOG"
err="$(python3 "$TOOL" 2>&1 >/dev/null)"
check "exempt_size honored" 0 "$(grep -c 'big.md: lines' <<<"$err")"
check "scope all reaches sub/" 1 "$(grep -c 'sub/out-of-scope.md' <<<"$err")"
check "exempt_frontmatter honored" 0 "$(grep -c 'docs/nofm.md' <<<"$err")"
check "exempt_all honored" 0 "$(grep -cE 'multi|vendored' <<<"$err")"
check "private path redacted" 0 "$(grep -c secret-title <<<"$err$(cat "$DOC_LINT_LOG")")"
check "private redaction shown" 1 "$(grep -c 'private/<redacted>' <<<"$err")"

# 10件を超える警告は省略表示
for i in $(seq 1 12); do printf 'x\n' > "w$i.md"; done
git add -A
err="$(python3 "$TOOL" 2>&1 >/dev/null)"
check "output truncated at 10" 1 "$(grep -c '\.\.\. and .* more' <<<"$err")"

# Doc-Lint-Override: 理由付きで追記
printf 'feat: x\n\nDoc-Lint-Override: 長い一次資料のため\n' > "$WORK/msg"
: >| "$DOC_LINT_LOG"
python3 "$TOOL" --commit-msg "$WORK/msg" 2>&1
check "override rows have reason column" "長い一次資料のため" "$(head -1 "$DOC_LINT_LOG" | cut -f7)"
printf 'feat: x\n' > "$WORK/msg2"
: >| "$DOC_LINT_LOG"
python3 "$TOOL" --commit-msg "$WORK/msg2"
check "no override, no rows" 0 "$(wc -l < "$DOC_LINT_LOG" | tr -d ' ')"

# --- グローバルフック経由: 警告が出ても commit が成功する ---
HREPO="$WORK/hookrepo"
mkdir -p "$HREPO" "$WORK/bin"
git -C "$HREPO" init -q
cd "$HREPO"
git config user.name t; git config user.email t@example.com
git config core.hooksPath "$ROOT/git/hooks"
cat > .pre-commit-config.yaml <<'YAML'
repos: []
# gitleaks detect-private-key detect-dotenv
YAML
# pre-commit コマンドは偽物(成功するだけ)を PATH 先頭に置く
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/pre-commit"; chmod +x "$WORK/bin/pre-commit"
export PATH="$WORK/bin:$PATH"
python3 -c "print('line\n' * 250, end='')" > big.md
git add -A
: >| "$DOC_LINT_LOG"
set +e
out="$(git commit -q -m 'docs: big' -m 'Doc-Lint-Override: テスト' 2>&1)"; rc=$?
set -e
check "commit succeeds despite warnings" 0 "$rc"
check "hook printed warning" 1 "$(grep -c 'doc-lint (warn only)' <<<"$out")"
check "log has warning and override rows" 4 "$(wc -l < "$DOC_LINT_LOG" | tr -d ' ')"
check "skip-policy-check skips" 0 "$(
  git config hooks.skip-policy-check true
  printf 'more\n' >> big.md; git add -A
  git commit -q -m 'docs: again' 2>&1 | grep -c 'doc-lint' || true)"

if ((FAILURES > 0)); then
  echo "$FAILURES failure(s)"
  exit 1
fi
echo "all passed"
