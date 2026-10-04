#!/usr/bin/env bash
# bin/unix/git-pull-all の回帰テスト。一時ディレクトリに使い捨ての git リポジトリ
# （bare origin + 作業用クローン）を作って検証する。ネットワークアクセスなし。
set -euo pipefail

PULL_ALL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/git-pull-all"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }
lacks() { [[ "$1" != *"$2"* ]]; }
rc_is() { [[ "$RC" -eq "$1" ]]; }
section() { echo; echo "== $1 =="; }
run() { OUT="$("$PULL_ALL" "$@" 2>&1)" && RC=0 || RC=$?; }
same() { [[ "$(git rev-parse "$1")" == "$(git rev-parse "$2")" ]]; }

setup_git() {
  git config user.email "git-pull-all-test@example.com"
  git config user.name "git-pull-all-test"
  git config hooks.skip-policy-check true
}

# 別クローンから origin のブランチを1コミット進める
remote_commit() {
  local branch="$1"
  (
    cd "$WORK/other"
    git fetch -q origin
    git checkout -q -B "$branch" "origin/$branch"
    echo "remote-$RANDOM" >> "$branch.txt"
    git add "$branch.txt"
    git commit -q -m "feat: remote update on $branch"
    git push -q origin "$branch"
  )
}

cd "$WORK"
git init -q --bare origin.git
git init -q repo
cd repo
setup_git
git remote add origin ../origin.git
echo hello > README.md
git add README.md
git commit -q -m "chore: init"
git branch -M main
git push -q -u origin main
git clone -q ../origin.git ../other
(cd ../other && setup_git)

for name in feat-a feat-b feat-div; do
  git checkout -q -b "$name" main
  echo "$name" > "$name.txt"
  git add "$name.txt"
  git commit -q -m "feat: $name"
  git push -q -u origin "$name"
done
git checkout -q main

section "current and other branches are fast-forwarded"
remote_commit main
remote_commit feat-a
remote_commit feat-b
git checkout -q feat-a
run
check "exit 0" rc_is 0
check "current branch pulled" same feat-a origin/feat-a
check "stays on current branch" [ "$(git rev-parse --abbrev-ref HEAD)" = "feat-a" ]
check "reports current update" contains "$OUT" "Updated feat-a."
check "protected branch fast-forwarded without checkout" same main origin/main
check "reports main update" contains "$OUT" "Updated main (fast-forward)."
check "other branch fast-forwarded" same feat-b origin/feat-b
check "reports other update" contains "$OUT" "Updated feat-b (fast-forward)."
run
check "second run is silent when up to date" lacks "$OUT" "Updated"

section "--fetch-only does not touch local branches"
remote_commit feat-a
remote_commit feat-b
run --fetch-only
check "exit 0" rc_is 0
check "current branch not pulled" [ "$(git rev-parse feat-a)" != "$(git rev-parse origin/feat-a)" ]
check "other branch not updated" [ "$(git rev-parse feat-b)" != "$(git rev-parse origin/feat-b)" ]
check "no update message" lacks "$OUT" "Updated"
run
check "next normal run catches up" same feat-b origin/feat-b

section "diverged other branch warns but exits 0"
git checkout -q feat-div
echo local-only >> feat-div.txt
git commit -q -am "feat: local-only on feat-div"
remote_commit feat-div
git checkout -q feat-a
run
check "exit 0" rc_is 0
check "diverged warned" contains "$OUT" "could not fast-forward feat-div (diverged)"
check "local commit preserved" [ "$(git log feat-div --oneline | command grep -c 'local-only on feat-div')" = "1" ]

section "local-ahead branch is silent"
git checkout -q -B feat-ahead main
git push -q -u origin feat-ahead
echo ahead >> README.md
git commit -q -am "feat: ahead only"
git checkout -q feat-a
run
check "no warning for ahead branch" lacks "$OUT" "feat-ahead"

section "diverged current branch fails with exit 1"
git checkout -q feat-div
run
check "exit 1" rc_is 1
check "error reported" contains "$OUT" "error: could not fast-forward feat-div"
check "local commit still preserved" [ "$(git log feat-div --oneline | command grep -c 'local-only on feat-div')" = "1" ]
git checkout -q feat-a

section "dirty worktree: current not pulled (warning), others still fast-forwarded"
remote_commit feat-a
remote_commit feat-b
echo "uncommitted" >> README.md
run
check "exit 0" rc_is 0
check "dirty warned" contains "$OUT" "uncommitted changes"
check "current not pulled" [ "$(git rev-parse feat-a)" != "$(git rev-parse origin/feat-a)" ]
check "other branch fast-forwarded" same feat-b origin/feat-b
check "uncommitted change preserved" grep -q uncommitted README.md
git checkout -q -- README.md

section "detached HEAD and missing upstream"
git checkout -q --detach
remote_commit feat-b
run
check "exit 0" rc_is 0
check "detached warned" contains "$OUT" "detached HEAD"
check "other branch still fast-forwarded" same feat-b origin/feat-b
git checkout -q -b local-only main
run
check "no-upstream warned" contains "$OUT" "no upstream configured for 'local-only'"
check "exit 0 (no upstream is not a failure)" rc_is 0
git checkout -q feat-a

section "gone upstream is silent"
git checkout -q -b feat-gone main
git push -q -u origin feat-gone
git push -q origin --delete feat-gone
run
check "no warning for gone upstream" lacks "$OUT" "no upstream configured"
check "exit 0" rc_is 0
git checkout -q feat-a

section "branch in another worktree is skipped, not updated"
remote_commit feat-b
WT="$WORK/wt"
git worktree add -q "$WT" feat-b
run
check "reports worktree skip" contains "$OUT" "Skipped: feat-b"
check "worktree branch untouched" [ "$(git rev-parse feat-b)" != "$(git rev-parse origin/feat-b)" ]
git worktree remove --force "$WT"

section "fetch failure exits 1"
git remote add broken /nonexistent/path.git
run
check "exit 1" rc_is 1
check "fetch failure reported" contains "$OUT" "git fetch failed"
git remote remove broken

section "missing local protected branch is created from origin"
git config local.repo-protected-branches "main,develop"
git push -q origin main:develop
git checkout -q feat-a
run
check "develop created" git show-ref --verify --quiet refs/heads/develop
check "reports creation" contains "$OUT" "Created local branch develop"
check "new branch tracks origin/develop" [ "$(git rev-parse --abbrev-ref "develop@{upstream}")" = "origin/develop" ]
(cd ../other && git fetch -q origin && git checkout -q -B develop origin/develop && echo more >> develop.txt && git add develop.txt && git commit -q -m "feat: develop update" && git push -q origin develop)
run
check "created branch is fast-forwarded on the next run" same develop origin/develop

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All git-pull-all regression checks passed."
else
  echo "$FAILURES git-pull-all regression check(s) failed." >&2
  exit 1
fi
