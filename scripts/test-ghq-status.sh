#!/usr/bin/env bash
# bin/unix/ghq-status の回帰テスト。偽の ghq root と使い捨ての git リポジトリ（bare origin +
# clone）を使い、通常の1リポジトリ表示と、git worktree add で作った追加worktreeの行表示を
# 検証する。ネットワークアクセスなし（ghq コマンドは必要）。
set -euo pipefail

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

command -v ghq >/dev/null 2>&1 || { echo "skip: ghq が見つかりません" >&2; exit 0; }

export GHQ_ROOT="$WORK/ghq"

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
# ANSI色コードを除いた上で判定する（表の色付けを気にせず内容だけ確認するため）。
_plain() { printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g'; }
contains() { [[ "$(_plain "$1")" == *"$2"* ]]; }
lacks() { [[ "$(_plain "$1")" != *"$2"* ]]; }

setup_git() {
  git config user.email "ghq-status-test@example.com"
  git config user.name "ghq-status-test"
  git config hooks.skip-policy-check true
}

# make_repo NAME: bare origin + ghq 管理下のクローン（main に1コミット、originにpush済み）
make_repo() {
  local name="$1" dir
  dir="$GHQ_ROOT/github.com/t/$name"
  git init -q --bare "$WORK/$name.git"
  mkdir -p "$(dirname "$dir")"
  git clone -q "$WORK/$name.git" "$dir" 2>/dev/null
  (
    cd "$dir"
    setup_git
    git checkout -q -b main 2>/dev/null || git checkout -q main
    echo init > README.md
    git add README.md
    git commit -q -m "chore: init"
    git push -q -u origin main
  )
}

repo() { printf '%s/github.com/t/%s' "$GHQ_ROOT" "$1"; }

section() { echo; echo "== $1 =="; }

echo "== plain repo (no linked worktree) stays a single, correct row =="
make_repo plain
OUT="$("$BIN/ghq-status" -a -f 'plain$' 2>&1)"
check "shows the real branch (regression: a local var named 'path' once clobbered \$PATH)" contains "$OUT" " main "
check "shows clean status" contains "$OUT" "✓"
check "does not add a spurious worktree row" lacks "$OUT" "↳"

section "repo with a linked worktree: main row + worktree row, independent branch/status"
make_repo withwt
git -C "$(repo withwt)" worktree add -q -b feature-x "$WORK/wt-feature-x" >/dev/null
echo dirty >> "$WORK/wt-feature-x/untracked.txt"

OUT="$("$BIN/ghq-status" -a -f 'withwt$' 2>&1)"
check "main repo row shows its own branch" contains "$OUT" " main "
check "main repo row is clean" contains "$OUT" "withwt"
check "worktree row is prefixed and labeled by its directory name" contains "$OUT" "↳ wt-feature-x"
check "worktree row shows its own branch, not the main repo's" contains "$OUT" "feature-x"
check "worktree row shows its own dirty status (1 untracked)" contains "$OUT" "?1"

echo
echo "-- default (no -a): repo has an extra local branch (feature-x) so policy_ok=0 and both rows show --"
OUT="$("$BIN/ghq-status" -f 'withwt$' 2>&1)"
check "main row still shown (repo-wide BRANCHES policy violation)" contains "$OUT" "withwt"
check "worktree row still shown" contains "$OUT" "↳ wt-feature-x"

echo
echo "-- -p/--paths-only reports both the repo and the worktree path --"
OUT="$("$BIN/ghq-status" -p -f 'withwt$' 2>&1)"
check "lists the main repo path" contains "$OUT" "$(repo withwt)"
check "lists the worktree path" contains "$OUT" "$WORK/wt-feature-x"

section "-f scopes worktree detection to the matching repo only"
OUT="$("$BIN/ghq-status" -a -f 'plain$' 2>&1)"
check "unrelated repo's worktree never leaks into an unfiltered repo's output" lacks "$OUT" "wt-feature-x"

section "-f matching nothing shows no repos (regression: empty filter once fell back to \$PWD)"
OUT="$("$BIN/ghq-status" -a -f 'no-such-repo-xyz' 2>&1)"
check "does not fall back to the current working directory" lacks "$OUT" "dotfiles"
check "does not show any fixture repo either" lacks "$OUT" "plain"
OUT="$("$BIN/ghq-status" -p -f 'no-such-repo-xyz' 2>&1)"
check "paths-only prints nothing" [ -z "$OUT" ]

echo
if (( FAILURES > 0 )); then echo "FAILED: $FAILURES" >&2; exit 1; fi
echo "all passed"
