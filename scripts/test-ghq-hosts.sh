#!/usr/bin/env bash
# bin/unix/ghq-hosts の回帰テスト。ssh と ghq-* は偽のコマンドに差し替えるため、
# 実際のホスト・リポジトリには一切影響しない。
set -euo pipefail

HOSTS_CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/ghq-hosts"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/private/ghq"
export DOTFILES_PRIVATE_DIR="$WORK/private"
export GHQ_HOSTS_LOG_DIR="$WORK/logs"
export CALLS="$WORK/calls"

for c in ghq-pull ghq-update ghq-sweep ghq-status; do
  cat > "$WORK/bin/$c" <<STUB
#!/usr/bin/env bash
echo "local $c \$*" >> "\$CALLS"
echo "local-out $c"
[[ "\${FAIL_LOCAL:-}" == "$c" ]] && exit 1
exit 0
STUB
  chmod +x "$WORK/bin/$c"
done

cat > "$WORK/ssh" <<'STUB'
#!/usr/bin/env bash
while [[ "$1" == -o ]]; do shift 2; done
host="$1"; shift
echo "$host $*" >> "$CALLS"
[[ "$host" == down ]] && { echo "ssh: connect timed out" >&2; exit 255; }
[[ "$host" == badsweep && "$*" == ghq-sweep ]] && { echo "sweep broke" >&2; exit 1; }
echo "remote-out $host $*"
STUB
chmod +x "$WORK/ssh"
export GHQ_HOSTS_SSH="$WORK/ssh"
export PATH="$WORK/bin:$PATH"

cat > "$WORK/private/ghq/hosts" <<'DECL'
# コメント
Alpha:  beta gamma   # 行末コメント
beta:   gamma
gamma:  beta
mixed:  beta down badsweep gamma
DECL

check() {
  local desc="$1"; shift
  if "$@"; then echo "  ok   - $desc"; else echo "  FAIL - $desc" >&2; FAILURES=$((FAILURES + 1)); fi
}
contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }
section() { echo; echo "== $1 =="; }

run() { : > "$CALLS"; OUT="$("$HOSTS_CMD" "$@" 2>&1)" && RC=0 || RC=$?; CALLS_OUT="$(sed 's/ *$//' "$CALLS")"; }
rc_is() { [[ "$RC" -eq "$1" ]]; }

section "dry-run"
run --from alpha --dry-run
check "exit 0" rc_is 0
check "lists remote command" contains "$OUT" "BatchMode=yes -o ConnectTimeout=5 beta ghq-pull"
check "lists local command" contains "$OUT" "would run: ghq-pull"
check "nothing executed" test ! -s "$CALLS"

section "default steps and order (case-insensitive --from)"
run --from ALPHA
check "exit 0" rc_is 0
expected="local ghq-pull
local ghq-sweep
local ghq-status
beta ghq-pull
beta ghq-sweep
beta ghq-status
gamma ghq-pull
gamma ghq-sweep
gamma ghq-status"
check "call order" [ "$CALLS_OUT" = "$expected" ]
check "summary shown" contains "$OUT" "== summary =="
check "success output hidden" not_contains "$OUT" "remote-out beta ghq-pull"
check "status output shown" contains "$OUT" "remote-out beta ghq-status"
check "log written" test -f "$GHQ_HOSTS_LOG_DIR/beta.log"

section "step selection"
run --from alpha --update --no-sweep --no-status -H beta --no-local
check "update only on beta" [ "$CALLS_OUT" = "beta ghq-update" ]
run --from alpha --no-pull --no-status --no-local
check "sweep only" [ "$CALLS_OUT" = "beta ghq-sweep
gamma ghq-sweep" ]
run --from alpha -a --no-pull --no-sweep --no-local -H gamma
check "status -a passed" [ "$CALLS_OUT" = "gamma ghq-status -a" ]
run --from alpha --no-pull --no-sweep --no-status
check "no steps is an error" rc_is 1

section "host selection"
run --from beta
check "beta targets gamma only (no alpha)" not_contains "$CALLS_OUT" "Alpha"
check "gamma reached" contains "$CALLS_OUT" "gamma ghq-pull"
run --from alpha -H nosuch
check "undeclared host rejected" rc_is 1
run --from nosuch
check "undeclared source rejected" rc_is 1
check "source error mentions --from" contains "$OUT" "--from"

section "failures continue"
run --from mixed --no-local
check "exit 1" rc_is 1
check "later host still ran" contains "$CALLS_OUT" "gamma ghq-status"
check "step after failing sweep still ran" contains "$CALLS_OUT" "badsweep ghq-status"
check "unreachable host stops its own steps" not_contains "$CALLS_OUT" "down ghq-sweep"
check "failure output shown" contains "$OUT" "sweep broke"
check "summary marks ssh failure" contains "$OUT" "ssh"
check "summary marks skip" contains "$OUT" "skip"
FAIL_LOCAL=ghq-pull run --from alpha -H beta
check "local failure exits 1" rc_is 1
check "remote still ran after local failure" contains "$CALLS_OUT" "beta ghq-status"

section "hosts.local and errors"
printf 'alpha: extra\n' > "$WORK/private/ghq/hosts.local"
run --from alpha --dry-run --no-local
check "hosts.local additive" contains "$OUT" "extra"
rm "$WORK/private/ghq/hosts.local"
printf 'alpha: -oProxyCommand=x\n' > "$WORK/private/ghq/hosts.local"
run --from alpha --dry-run
check "option-like host rejected" rc_is 1
rm "$WORK/private/ghq/hosts.local"
mv "$WORK/private/ghq/hosts" "$WORK/private/ghq/hosts.bak"
run --from alpha --dry-run
check "missing declaration is an error" rc_is 1
mv "$WORK/private/ghq/hosts.bak" "$WORK/private/ghq/hosts"

echo
if [[ "$FAILURES" -ne 0 ]]; then echo "$FAILURES 件失敗" >&2; exit 1; fi
echo "すべて成功"
