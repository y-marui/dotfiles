#!/usr/bin/env bash
# ghq/keep-up-to-date.sh の回帰テスト。一時ディレクトリに偽の ghq root と使い捨ての
# git リポジトリ、偽の dotfiles-private を作って検証する。ネットワークアクセスは行わず、
# 実際の ghq root・dotfiles-private には一切影響しない（ghq コマンドは必要）。
set -euo pipefail

KEEP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ghq/keep-up-to-date.sh"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

if ! command -v ghq >/dev/null 2>&1; then
  echo "skip: ghq が見つかりません" >&2
  exit 0
fi

export GHQ_ROOT="$WORK/ghq"
export DOTFILES_PRIVATE_DIR="$WORK/private"
DECL="$DOTFILES_PRIVATE_DIR/ghq/keep-up-to-date"
LOCAL="$DECL.local"

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

contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }
section() { echo; echo "== $1 =="; }

repo_path() { printf '%s/%s' "$GHQ_ROOT" "$1"; }
value_of() { git -C "$(repo_path "$1")" config --local --get local.keep-up-to-date 2>/dev/null || true; }
set_true() { git -C "$(repo_path "$1")" config --local --bool local.keep-up-to-date true; }
set_false() { git -C "$(repo_path "$1")" config --local --bool local.keep-up-to-date false; }

reset_env() {
  rm -rf "$GHQ_ROOT" "$WORK/ghq2" "$DOTFILES_PRIVATE_DIR"
  mkdir -p "$DOTFILES_PRIVATE_DIR/ghq"
  local r
  for r in github.com/o/alpha github.com/o/beta github.com/o/Gamma github.com/o/delta; do
    mkdir -p "$(repo_path "$r")"
    git init -q "$(repo_path "$r")"
  done
}

run() { "$KEEP" "$@" 2>&1; }

section "diff"
reset_env
printf '%s\n' '# header' 'github.com/o/alpha' > "$DECL"
set_true github.com/o/beta
output=$(run diff) && rc=0 || rc=$?
check "diff exits 1 when there is a difference" [ "$rc" -eq 1 ]
check "reports true-but-undeclared repo" contains "$output" "[+actual]  github.com/o/beta"
check "reports declared-but-not-true repo" contains "$output" "[-file]  github.com/o/alpha"
output=$(run diff --summary) && rc=0 || rc=$?
check "summary counts both kinds" [ "$output" = "+1 宣言なし / -1 未適用" ]
printf '%s\n' 'github.com/o/alpha' 'github.com/o/beta' > "$DECL"
set_true github.com/o/alpha
output=$(run diff) && rc=0 || rc=$?
check "diff exits 0 when in sync" [ "$rc" -eq 0 ]
output=$(run diff --summary) && rc=0 || rc=$?
check "summary is silent when in sync" [ -z "$output" ]

section "case-insensitive and trailing-slash matching"
reset_env
printf '%s\n' 'GitHub.com/o/GAMMA/' > "$DECL"
set_true github.com/o/Gamma
output=$(run diff) && rc=0 || rc=$?
check "declaration matches ignoring case and trailing slash" [ "$rc" -eq 0 ]

section "unfetched entries are ignored"
reset_env
printf '%s\n' 'github.com/o/missing' 'github.com/o/alpha' > "$DECL"
set_true github.com/o/alpha
output=$(run diff) && rc=0 || rc=$?
check "diff ignores unfetched entry" [ "$rc" -eq 0 ]
run apply >/dev/null
check "apply leaves alpha true" [ "$(value_of github.com/o/alpha)" = "true" ]
run sync >/dev/null
check "sync keeps unfetched entry" grep -qx 'github.com/o/missing' "$DECL"

section ".local extends the declaration"
reset_env
printf '%s\n' 'github.com/o/alpha' > "$DECL"
printf '%s\n' 'github.com/o/beta' > "$LOCAL"
set_true github.com/o/alpha
set_true github.com/o/beta
output=$(run diff) && rc=0 || rc=$?
check "local-declared true repo is not reported" [ "$rc" -eq 0 ]
run sync >/dev/null
check "sync does not promote local-declared repo" not_contains "$(cat "$DECL")" "beta"
check "sync leaves .local untouched" [ "$(cat "$LOCAL")" = "github.com/o/beta" ]

section "apply"
reset_env
printf '%s\n' 'github.com/o/alpha' 'github.com/o/missing' > "$DECL"
set_true github.com/o/beta
set_false github.com/o/delta
output=$(run apply)
check "sets declared+fetched repo" [ "$(value_of github.com/o/alpha)" = "true" ]
check "unsets undeclared true repo" [ -z "$(value_of github.com/o/beta)" ]
check "leaves explicit false alone" [ "$(value_of github.com/o/delta)" = "false" ]
check "reports set/unset counts" contains "$output" "1 set / 1 unset"
output=$(run apply)
check "second apply changes nothing" contains "$output" "No change"

section "merge"
reset_env
printf '%s\n' '# keep me' 'github.com/o/alpha' > "$DECL"
set_true github.com/o/beta
run merge >/dev/null
check "merge adds true-but-undeclared repo" grep -qx 'github.com/o/beta' "$DECL"
check "merge keeps stale entry" grep -qx 'github.com/o/alpha' "$DECL"
check "merge keeps comment" grep -qx '# keep me' "$DECL"

section "sync"
reset_env
printf '%s\n' '# keep me' '' 'github.com/o/zeta' 'github.com/o/alpha' 'github.com/o/missing' > "$DECL"
set_true github.com/o/Gamma
set_true github.com/o/beta
output=$(run sync) && rc=0 || rc=$?
check "sync that removes entries needs --yes" [ "$rc" -eq 2 ]
check "sync failure asks for --yes" contains "$output" "--yes"
check "sync failure leaves the declaration alone" not_contains "$(cat "$DECL")" "beta"
output=$(run sync --dry-run)
check "sync --dry-run lists the removal" contains "$output" "[remove] github.com/o/alpha"
check "sync --dry-run leaves the declaration alone" grep -qx 'github.com/o/alpha' "$DECL"
output=$(run sync --yes)
check "sync adds true repos" grep -qx 'github.com/o/beta' "$DECL"
check "sync adds with original spelling" grep -qx 'github.com/o/Gamma' "$DECL"
check "sync removes fetched non-true repo" not_contains "$(cat "$DECL")" "alpha"
check "sync keeps unfetched entry" grep -qx 'github.com/o/missing' "$DECL"
check "sync keeps comment header" grep -qx '# keep me' "$DECL"
check "sync sorts entries" [ "$(grep -v '^#' "$DECL" | grep -v '^$')" = "$(grep -v '^#' "$DECL" | grep -v '^$' | sort -f)" ]
check "sync makes diff clean" run diff >/dev/null
output=$(run sync)
check "second sync changes nothing" contains "$output" "No change"

section "apply --no-prune / prune / --dry-run"
reset_env
printf '%s\n' 'github.com/o/alpha' > "$DECL"
set_true github.com/o/beta
output=$(run apply --dry-run)
check "apply --dry-run lists the set" contains "$output" "[dry-run] [set]    github.com/o/alpha"
check "apply --dry-run lists the unset" contains "$output" "[dry-run] [unset]  github.com/o/beta"
check "apply --dry-run does not set" [ -z "$(value_of github.com/o/alpha)" ]
check "apply --dry-run does not unset" [ "$(value_of github.com/o/beta)" = "true" ]
output=$(run apply --no-prune)
check "apply --no-prune sets declared repo" [ "$(value_of github.com/o/alpha)" = "true" ]
check "apply --no-prune keeps undeclared true repo" [ "$(value_of github.com/o/beta)" = "true" ]
check "apply --no-prune points to prune" contains "$output" "dots ghq prune"
output=$(run prune --dry-run)
check "prune --dry-run lists the unset" contains "$output" "[dry-run] [unset]  github.com/o/beta"
check "prune --dry-run does not unset" [ "$(value_of github.com/o/beta)" = "true" ]
output=$(run prune)
check "prune unsets undeclared true repo" [ -z "$(value_of github.com/o/beta)" ]
check "prune keeps declared true repo" [ "$(value_of github.com/o/alpha)" = "true" ]
set_false github.com/o/delta
set_true github.com/o/beta
printf '%s\n' 'github.com/o/alpha' 'github.com/o/delta' > "$DECL"
output=$(run prune)
check "prune does not set declared repos" [ "$(value_of github.com/o/delta)" = "false" ]
output=$(run prune)
check "second prune changes nothing" contains "$output" "No change"
output=$(run merge --dry-run)
check "merge --dry-run leaves the declaration alone" not_contains "$(cat "$DECL")" "beta"
output=$(run apply --yes) && rc=0 || rc=$?
check "--yes is only for sync" [ "$rc" -eq 2 ]
output=$(run prune --no-prune) && rc=0 || rc=$?
check "--no-prune is only for apply" [ "$rc" -eq 2 ]
output=$(run diff --dry-run) && rc=0 || rc=$?
check "--dry-run is not for diff" [ "$rc" -eq 2 ]

section "missing declaration"
reset_env
rm -f "$DECL"
output=$(run diff --summary) && rc=0 || rc=$?
check "summary is silent without declaration" [ "$rc" -eq 0 ]
check "summary prints nothing without declaration" [ -z "$output" ]
output=$(run apply) && rc=0 || rc=$?
check "apply refuses without declaration" [ "$rc" -eq 2 ]
output=$(run diff) && rc=0 || rc=$?
check "diff reports an error (not a difference) without declaration" [ "$rc" -eq 2 ]

section "exit codes"
reset_env
printf '%s\n' 'github.com/o/alpha' > "$DECL"
output=$(run diff) && rc=0 || rc=$?
check "diff exits 1 for a difference" [ "$rc" -eq 1 ]
output=$(run bogus) && rc=0 || rc=$?
check "unknown action exits 2" [ "$rc" -eq 2 ]
output=$(PATH=/usr/bin:/bin run diff) && rc=0 || rc=$?
check "missing ghq exits 2" [ "$rc" -eq 2 ]
output=$(PATH=/usr/bin:/bin run diff --summary) && rc=0 || rc=$?
check "missing ghq is silent for --summary" [ "$rc" -eq 0 ]
printf '%s\n' 'github.com/o/alpha' > "$DECL"
output=$(cd "$WORK" && "$KEEP" diff 2>&1) && rc=0 || rc=$?
check "diff from another cwd still exits 1 for a difference" [ "$rc" -eq 1 ]

section "multiple ghq roots"
reset_env
mkdir -p "$WORK/ghq2/github.com/o/second"
git init -q "$WORK/ghq2/github.com/o/second"
git -C "$WORK/ghq2/github.com/o/second" config --local --bool local.keep-up-to-date true
printf '%s\n' 'github.com/o/second' > "$DECL"
output=$(GHQ_ROOT="$GHQ_ROOT:$WORK/ghq2" run diff) && rc=0 || rc=$?
check "repo under a secondary root matches its relative declaration" [ "$rc" -eq 0 ]
: > "$DECL"
GHQ_ROOT="$GHQ_ROOT:$WORK/ghq2" run merge >/dev/null
check "merge writes a root-relative path" grep -qx 'github.com/o/second' "$DECL"

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
