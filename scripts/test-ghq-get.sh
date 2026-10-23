#!/usr/bin/env bash
# ghq/get.sh と scripts/host-role.sh の回帰テスト。偽の ghq root・dotfiles-private・
# ローカルの bare リポジトリを使い、ネットワークには触れない（ghq コマンドは必要）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GET="${ROOT_DIR}/ghq/get.sh"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

command -v ghq >/dev/null 2>&1 || { echo "skip: ghq が見つかりません" >&2; exit 0; }

export GHQ_ROOT="$WORK/ghq"
export DOTFILES_PRIVATE_DIR="$WORK/private"
export DOTFILES_DIR="$WORK/dotfiles"
mkdir -p "$GHQ_ROOT" "$DOTFILES_PRIVATE_DIR/ghq" "$DOTFILES_DIR/scripts" "$DOTFILES_DIR/host"
cp "$ROOT_DIR/scripts/host-role.sh" "$DOTFILES_DIR/scripts/"

# ghq get の取得元は file:// の bare リポジトリで代用する。
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$WORK/remote/.insteadOf"
export GIT_CONFIG_VALUE_0="https://example.test/"
for r in alpha beta; do
  git init -q --bare "$WORK/remote/o/$r.git"
  tmp="$WORK/seed-$r"
  git init -q "$tmp"
  git -C "$tmp" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$tmp" push -q "$WORK/remote/o/$r.git" HEAD:refs/heads/main 2>/dev/null
done

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }

printf '%s\n' '# c' 'example.test/o/alpha' 'example.test/o/beta # 後ろのコメント' > "$DOTFILES_PRIVATE_DIR/ghq/get"
export DOTS_HOST_ROLE=

echo "== role =="
unset DOTS_HOST_ROLE
check "unset when host/role is missing" [ "$(DOTFILES_DIR=$DOTFILES_DIR bash -c 'source "$DOTFILES_DIR/scripts/host-role.sh"; dots_host_role')" = unset ]
echo work > "$DOTFILES_DIR/host/role"
check "work from host/role" [ "$(bash -c 'source "$DOTFILES_DIR/scripts/host-role.sh"; dots_host_role')" = work ]
check "env overrides host/role" [ "$(DOTS_HOST_ROLE=other bash -c 'source "$DOTFILES_DIR/scripts/host-role.sh"; dots_host_role')" = other ]
check "invalid role" [ "$(DOTS_HOST_ROLE=foo bash -c 'source "$DOTFILES_DIR/scripts/host-role.sh"; dots_host_role')" = invalid ]

echo "== get =="
out=$(DOTS_HOST_ROLE=other bash "$GET" 2>&1)
check "other role skips" contains "$out" "skip"
check "other role fetches nothing" [ -z "$(ghq list)" ]
out=$(bash "$GET" --dry-run 2>&1)
check "dry-run lists both" contains "$out" "example.test/o/beta"
check "dry-run fetches nothing" [ -z "$(ghq list)" ]
out=$(bash "$GET" --summary 2>&1) && rc=0 || rc=$?
check "summary reports missing with exit 1" [ "$rc" -eq 1 ] && check "summary text" contains "$out" "-2 未取得"
out=$(bash "$GET" 2>&1)
check "get fetches both" [ "$(ghq list | wc -l | tr -d ' ')" = 2 ]
out=$(bash "$GET" 2>&1)
check "second run is idempotent" contains "$out" "0 get / 2 already fetched"
bash "$GET" --summary >/dev/null && check "summary clean" true || check "summary clean" false
printf 'example.test/o/missing\n' > "$DOTFILES_PRIVATE_DIR/ghq/get.local"
out=$(bash "$GET" 2>&1) && rc=0 || rc=$?
check "failed get exits 1" [ "$rc" -eq 1 ]
check "failed get is reported" contains "$out" "[failed]"

echo
if (( FAILURES > 0 )); then echo "FAILED: $FAILURES" >&2; exit 1; fi
echo "all passed"
