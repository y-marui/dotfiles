#!/usr/bin/env bash
# bin/unix/ghq-pull・ghq-update・ghq-sweep の回帰テスト。一時ディレクトリに偽の ghq root と
# 使い捨ての git リポジトリを作って検証する（ghq コマンドは必要）。ネットワークアクセスなし。
# 依存更新（uv sync / npm update）と自動 PR は対象外。
set -euo pipefail

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

if ! command -v ghq >/dev/null 2>&1; then
  echo "skip: ghq が見つかりません" >&2
  exit 0
fi

export GHQ_ROOT="$WORK/ghq"
export PATH="$BIN:$PATH"

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }
lacks() { [[ "$1" != *"$2"* ]]; }
rc_is() { [[ "$RC" -eq "$1" ]]; }
section() { echo; echo "== $1 =="; }
run() { OUT="$("$@" 2>&1)" && RC=0 || RC=$?; }
repo() { printf '%s/github.com/t/%s' "$GHQ_ROOT" "$1"; }
branch_absent() { ! git -C "$(repo "$1")" show-ref --verify --quiet "refs/heads/$2"; }
same() { [[ "$(git -C "$(repo "$1")" rev-parse "$2")" == "$(git -C "$(repo "$1")" rev-parse "$3")" ]]; }

setup_git() {
  git config user.email "ghq-test@example.com"
  git config user.name "ghq-test"
  git config hooks.skip-policy-check true
}

# make_repo NAME: bare origin + ghq 管理下のクローン（main に1コミット）
make_repo() {
  local name="$1"
  git init -q --bare "$WORK/$name.git"
  mkdir -p "$(dirname "$(repo "$name")")"
  git clone -q "$WORK/$name.git" "$(repo "$name")" 2>/dev/null
  (
    cd "$(repo "$name")"
    setup_git
    git checkout -q -b main 2>/dev/null || git checkout -q main
    echo init > README.md
    git add README.md
    git commit -q -m "chore: init"
    git push -q -u origin main
  )
  git clone -q "$WORK/$name.git" "$WORK/$name-other" 2>/dev/null
  (cd "$WORK/$name-other" && setup_git)
}

# remote_commit NAME BRANCH [FILE]: 別クローンから origin のブランチを進める
remote_commit() {
  local name="$1" branch="$2" file="${3:-$2.txt}"
  (
    cd "$WORK/$name-other"
    git fetch -q origin
    git checkout -q -B "$branch" "origin/$branch"
    echo "remote-$RANDOM" >> "$file"
    git add "$file"
    git commit -q -m "feat: remote update on $branch"
    git push -q origin "$branch"
  )
}

make_repo a-ok
make_repo b-diverged
make_repo c-dirty
make_repo d-lock
make_repo e-last

section "ghq-pull: success, failure isolation, warnings, lockfile stash"
remote_commit a-ok main README.md
remote_commit b-diverged main README.md
echo local >> "$(repo b-diverged)/local.txt"
git -C "$(repo b-diverged)" add local.txt
git -C "$(repo b-diverged)" commit -q -m "feat: local-only on main"
remote_commit c-dirty main README.md
echo dirty >> "$(repo c-dirty)/untracked.txt"
printf 'lock-local\n' > "$(repo d-lock)/uv.lock"
remote_commit e-last main README.md
run ghq-pull
check "exit 1 when one repo fails" rc_is 1
check "failing repo reported" contains "$OUT" "[failed] pull"
check "diverged error shown" contains "$OUT" "could not fast-forward main"
check "ok repo pulled" same a-ok HEAD origin/main
check "repo after the failure still pulled" same e-last HEAD origin/main
check "dirty warned, not a failure" contains "$OUT" "uncommitted changes"
check "dirty repo current branch not pulled" [ "$(git -C "$(repo c-dirty)" rev-parse HEAD)" != "$(git -C "$(repo c-dirty)" rev-parse origin/main)" ]
check "lockfile-only dirty repo pulled" same d-lock HEAD origin/main
check "lockfile restored after pull" grep -q lock-local "$(repo d-lock)/uv.lock"

section "ghq-pull: exit 0 when nothing fails; -f and --fetch-only"
remote_commit a-ok main README.md
run ghq-pull -f 'a-ok$' --fetch-only
check "exit 0" rc_is 0
check "fetch-only keeps main behind" [ "$(git -C "$(repo a-ok)" rev-parse HEAD)" != "$(git -C "$(repo a-ok)" rev-parse origin/main)" ]
check "filter excludes other repos" lacks "$OUT" "b-diverged"
run ghq-pull -f 'a-ok$'
check "normal pull catches up" same a-ok HEAD origin/main
check "exit 0 with clean pull" rc_is 0
run ghq-pull --uv-sync-only
check "unknown option rejected" rc_is 1

section "ghq-update: pull failure is counted, dirty skipped"
remote_commit a-ok main README.md
run ghq-update --pull-all --pull-only
check "exit 1 (diverged repo fails)" rc_is 1
check "failure reported" contains "$OUT" "[failed] pull"
check "ok repo pulled" same a-ok HEAD origin/main
check "dirty repo skipped" contains "$OUT" "[skip] dirty working tree"
run ghq-update --uv-sync-only
check "old --uv-sync-only rejected" rc_is 1
run ghq-update --sync-only --pull-only
check "--sync-only and --pull-only conflict" rc_is 1

section "ghq-sweep: pulls by default, --no-pull leaves local branches"
git -C "$(repo a-ok)" checkout -q -b feat-merged
echo m > "$(repo a-ok)/m.txt"
git -C "$(repo a-ok)" add m.txt
git -C "$(repo a-ok)" commit -q -m "feat: merged"
git -C "$(repo a-ok)" push -q -u origin feat-merged
git -C "$(repo a-ok)" checkout -q main
git -C "$(repo a-ok)" merge -q feat-merged
git -C "$(repo a-ok)" push -q origin main
remote_commit a-ok main README.md
run ghq-sweep --no-pull -f 'a-ok$'
check "exit 0" rc_is 0
check "merged branch deleted" branch_absent a-ok feat-merged
check "--no-pull leaves main behind" [ "$(git -C "$(repo a-ok)" rev-parse HEAD)" != "$(git -C "$(repo a-ok)" rev-parse origin/main)" ]
run ghq-sweep -f 'a-ok$'
check "default sweep pulls" same a-ok HEAD origin/main

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All ghq pull/update/sweep regression checks passed."
else
  echo "$FAILURES ghq pull/update/sweep regression check(s) failed." >&2
  exit 1
fi
