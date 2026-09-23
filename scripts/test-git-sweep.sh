#!/usr/bin/env bash
# bin/unix/git-sweep の回帰テスト。一時ディレクトリに使い捨ての git リポジトリ
# （bare origin + 作業用クローン）を作り、削除・保存の境界ケースを検証する。
# ネットワークアクセスは行わない。リポジトリ外には一切影響しない。
set -euo pipefail

SWEEP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/git-sweep"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  ok   - $desc"
  else
    echo "  FAIL - $desc" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

branch_exists() { git show-ref --verify --quiet "refs/heads/$1"; }
branch_absent() { ! git show-ref --verify --quiet "refs/heads/$1"; }
contains() { [[ "$1" == *"$2"* ]]; }

section() { echo; echo "== $1 =="; }

cd "$WORK"
git init --bare -q origin.git

git init -q repo
cd repo
git config user.email "git-sweep-test@example.com"
git config user.name "git-sweep-test"
# Some environments install a global template hook that requires
# .pre-commit-config.yaml in every new repo. This is a throwaway test repo.
git config hooks.skip-policy-check true
git remote add origin ../origin.git
echo "hello" > README.md
git add README.md
git commit -q -m "chore: init"
git branch -M main
git push -q -u origin main

section "ordinary merged-branch cleanup (fast-forward / merge commit)"
git checkout -q -b feature-ff
echo "line" >> README.md
git commit -q -am "feat: ff change"
git push -q -u origin feature-ff
git checkout -q main
git merge -q feature-ff
git push -q origin main
git checkout -q feature-ff
output=$("$SWEEP" 2>&1)
check "feature-ff deleted" branch_absent feature-ff
check "switched back to main" [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
check "reports deletion" contains "$output" "Deleted: feature-ff"

section "squash-merge (gone) verified as integrated"
git checkout -q main
git checkout -q -b feature-squash
echo "squash-line-1" > squash.txt
git add squash.txt
git commit -q -m "wip 1"
echo "squash-line-2" >> squash.txt
git commit -q -am "wip 2"
git push -q -u origin feature-squash
git checkout -q main
git -c merge.ff=true merge -q --squash feature-squash
git commit -q -m "feat: squash merged feature-squash"
git push -q origin main
git push -q origin --delete feature-squash
git checkout -q feature-squash
git fetch -q --prune
output=$("$SWEEP" 2>&1)
check "feature-squash deleted" branch_absent feature-squash
check "reports verified squash deletion" contains "$output" "squash/rebase merge, verified"

section "gone upstream but NOT integrated is preserved (unmerged commits)"
git checkout -q main
git checkout -q -b feature-orphan
echo "orphan-change" > orphan.txt
git add orphan.txt
git commit -q -m "feat: orphan change never merged"
git push -q -u origin feature-orphan
git push -q origin --delete feature-orphan
git fetch -q --prune
output=$("$SWEEP" 2>&1)
check "feature-orphan preserved" branch_exists feature-orphan
check "reports not yet merged" contains "$output" "not yet merged"

section "gone upstream with additional local-only commits is preserved"
git checkout -q main
git checkout -q -b feature-extra
echo "extra-1" > extra.txt
git add extra.txt
git commit -q -m "wip extra 1"
git push -q -u origin feature-extra
git checkout -q main
git -c merge.ff=true merge -q --squash feature-extra
git commit -q -m "feat: squash merged feature-extra"
git push -q origin main
git push -q origin --delete feature-extra
git checkout -q feature-extra
echo "extra-2-local-only" >> extra.txt
git commit -q -am "wip extra 2 (local only, not part of the squash merge)"
git fetch -q --prune
output=$("$SWEEP" 2>&1)
check "feature-extra preserved (extra local commit not covered by squash)" branch_exists feature-extra

section "local main behind origin/main (merged remotely) is fast-forwarded before the merge check"
git checkout -q main
git checkout -q -b feature-remote-merge
echo "remote-merge-change" >> README.md
git commit -q -am "feat: remote-merge change"
git push -q -u origin feature-remote-merge
git clone -q ../origin.git ../merger-clone
(
  cd ../merger-clone
  git config user.email "merger@example.com"
  git config user.name "merger"
  git config hooks.skip-policy-check true
  git checkout -q feature-remote-merge
  git checkout -q main
  git merge -q feature-remote-merge
  git push -q origin main
)
# Local main is intentionally NOT pulled here, simulating a PR merged on the
# remote (e.g. via GitHub) before the local clone's main branch caught up.
git checkout -q feature-remote-merge
output=$("$SWEEP" 2>&1)
check "reports local main fast-forward" contains "$output" "Updated main (fast-forward)"
check "feature-remote-merge deleted" branch_absent feature-remote-merge
check "switched back to main" [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
check "local main now matches origin/main" [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]

section "dirty worktree on a merged branch is preserved untouched"
git checkout -q main
git checkout -q -b feature-dirty
echo "dirty-change" >> README.md
git commit -q -am "feat: dirty change"
git push -q -u origin feature-dirty
git checkout -q main
git merge -q feature-dirty
git push -q origin main
git checkout -q feature-dirty
echo "uncommitted local edit" >> README.md
output=$("$SWEEP" 2>&1)
check "stays on feature-dirty (no checkout attempted)" [ "$(git rev-parse --abbrev-ref HEAD)" = "feature-dirty" ]
check "feature-dirty not deleted" branch_exists feature-dirty
check "uncommitted change preserved" grep -q "uncommitted local edit" README.md
check "reports dirty-worktree skip" contains "$output" "uncommitted changes"
git checkout -q -- README.md

section "branch checked out in another worktree is skipped, not force-deleted"
git checkout -q main
git checkout -q -b feature-worktree
echo "wt-change" >> README.md
git commit -q -am "feat: worktree change"
git push -q -u origin feature-worktree
git checkout -q main
git merge -q feature-worktree
git push -q origin main
WT_DIR="$WORK/linked-worktree"
git worktree add -q "$WT_DIR" feature-worktree
output=$("$SWEEP" --all 2>&1)
check "feature-worktree preserved" branch_exists feature-worktree
check "reports worktree skip" contains "$output" "Skipped: feature-worktree"
check "linked worktree untouched" [ "$(git -C "$WT_DIR" rev-parse --abbrev-ref HEAD)" = "feature-worktree" ]
git worktree remove --force "$WT_DIR"
git branch -D feature-worktree > /dev/null

section "diverged protected branch is preserved, not rebased"
git config local.repo-protected-branches "main,develop"
git checkout -q main
git checkout -q -b develop
echo "develop-base" > develop.txt
git add develop.txt
git commit -q -m "feat: develop base"
git push -q -u origin develop

git clone -q ../origin.git ../other-clone
(
  cd ../other-clone
  git config user.email "other@example.com"
  git config user.name "other"
  git config hooks.skip-policy-check true
  git checkout -q develop
  echo "develop-remote" >> develop.txt
  git commit -q -am "feat: remote-only develop change"
  git push -q origin develop
)

echo "develop-local-only" >> develop.txt
git commit -q -am "feat: local-only develop change (diverged from origin)"
git checkout -q main
output=$("$SWEEP" 2>&1)
check "local develop commit preserved (not rebased away)" [ "$(git log develop --oneline | command grep -c 'local-only develop change')" = "1" ]
check "reports could-not-fast-forward warning for develop" contains "$output" "could not fast-forward develop"
check "develop still 1 commit ahead of merge-base (no rebase happened)" [ "$(git rev-list --count "$(git merge-base develop origin/develop)..develop")" = "1" ]

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All git-sweep regression checks passed."
  exit 0
else
  echo "$FAILURES git-sweep regression check(s) failed." >&2
  exit 1
fi
