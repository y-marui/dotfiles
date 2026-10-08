#!/usr/bin/env bash
# bin/unix/_git-fork-lib.sh の upstream 同期（gh 未認証時の git フォールバック）の
# 回帰テスト。一時ディレクトリに使い捨ての bare リポジトリ（upstream・fork）と
# 作業用クローンを作って検証する。ネットワークアクセスなし。
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/_git-fork-lib.sh"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }
lacks() { [[ "$1" != *"$2"* ]]; }
section() { echo; echo "== $1 =="; }
head_of() { git -C "$1" rev-parse refs/heads/main; }

setup_git() {
  git config user.email "git-fork-sync-test@example.com"
  git config user.name "git-fork-sync-test"
  git config hooks.skip-policy-check true
}

# upstream に1コミット進める（別クローン経由）
upstream_commit() {
  (
    cd "$WORK/other"
    git pull -q origin main
    echo "up-$RANDOM" >> up.txt
    git add up.txt
    git commit -q -m "feat: upstream update"
    git push -q origin main
  )
}

# shellcheck source=../bin/unix/_git-fork-lib.sh
source "$LIB"

# gh が未認証である状態を再現する（macOS の SSH セッションでキーチェーンを読めない状況）
gh() { return 1; }

cd "$WORK"
git init -q --bare -b main upstream.git
git init -q --bare -b main fork.git
git clone -q upstream.git other 2>/dev/null
(cd other && setup_git && echo base > README.md && git add README.md && git commit -q -m "chore: init" && git push -q origin main)
git clone -q fork.git repo 2>/dev/null
(
  cd repo
  setup_git
  git remote add upstream ../upstream.git
  git fetch -q upstream
  git push -q origin refs/remotes/upstream/main:refs/heads/main
)

run_sync() { OUT="$(_git_fork_sync_upstream "$WORK/repo" 2>&1)"; }

section "fork is behind upstream: fast-forwarded via git"
upstream_commit
run_sync
check "falls back to git" contains "$OUT" "git で同期します"
check "reports synced" contains "$OUT" "同期しました（git）"
check "fork main equals upstream main" [ "$(head_of "$WORK/fork.git")" = "$(head_of "$WORK/upstream.git")" ]

section "already up to date: nothing happens"
run_sync
check "no sync message" lacks "$OUT" "同期しました"
check "no warning" lacks "$OUT" "[warn]"

section "fork diverged: not overwritten"
(
  cd "$WORK/repo"
  git pull -q origin main
  echo local > local.txt
  git add local.txt
  git commit -q -m "feat: fork only"
  git push -q origin main
)
upstream_commit
before="$(head_of "$WORK/fork.git")"
run_sync
check "warns about divergence" contains "$OUT" "分岐しているため同期しません"
check "fork main unchanged" [ "$(head_of "$WORK/fork.git")" = "$before" ]

section "upstream unreachable: warns and returns 0"
git -C "$WORK/repo" remote set-url upstream "$WORK/missing.git"
run_sync && rc=0 || rc=$?
check "skipped" contains "$OUT" "[skip upstream-sync]"
check "exit 0" [ "$rc" -eq 0 ]

section "no upstream remote: silent"
git -C "$WORK/repo" remote remove upstream
run_sync
check "no output" [ -z "$OUT" ]

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All git-fork-sync regression checks passed."
else
  echo "$FAILURES git-fork-sync regression check(s) failed." >&2
  exit 1
fi
