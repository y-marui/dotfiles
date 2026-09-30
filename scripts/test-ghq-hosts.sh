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
[[ "\${WARN_LOCAL:-}" == "$c" ]] && { echo "==> /repo/a"; echo "  [skip pull] dirty working tree"; }
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
[[ "$host" == slow* ]] && sleep 2
[[ "$host" == down ]] && { echo "ssh: connect timed out" >&2; exit 255; }
[[ "$host" == badsweep && "$*" == ghq-sweep ]] && { echo "sweep broke" >&2; exit 1; }
[[ "$host" == warnhost && "$*" == ghq-pull ]] && { echo "==> /repo/b"; echo "  [skip pull] dirty working tree"; }
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
par:    slow1 slow2
warn:   warnhost beta
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
run --from ALPHA -j 1
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

section "parallel hosts"
start=$SECONDS
run --from par --no-local --no-sweep --no-status
elapsed=$((SECONDS - start))
check "exit 0" rc_is 0
check "hosts run concurrently (2s sleeps finish well under 4s)" test "$elapsed" -lt 4
check "both hosts ran" contains "$CALLS_OUT" "slow2 ghq-pull"
in_order() { [[ "$1" == *"==> slow1"*"==> slow2"* ]]; }
check "output kept in declared order" in_order "$OUT"
start=$SECONDS
run --from par --no-local --no-sweep --no-status -j 1
elapsed=$((SECONDS - start))
check "-j 1 is sequential (>= 4s)" test "$elapsed" -ge 4
run --from par --no-local -j 0
check "invalid --jobs rejected" rc_is 1

section "progress display"
run --from par --no-local --no-sweep --no-status
check "no escape sequences when stderr is not a terminal" not_contains "$OUT" $'\033['
# 擬似端末（pty）で実行して出力を集める
run_pty() {
  python3 - "$@" <<'PY'
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
chunks = []
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    chunks.append(data)
os.waitpid(pid, 0)
sys.stdout.write(b"".join(chunks).decode("utf-8", "replace"))
PY
}
if command -v python3 >/dev/null 2>&1; then
  PTY_OUT="$(run_pty "$HOSTS_CMD" --from par --no-local --no-sweep --no-status || true)"
  check "progress drawn on a terminal" contains "$PTY_OUT" $'\033[?25l'
  check "cursor restored" contains "$PTY_OUT" $'\033[?25h'
  check "host shown in progress" contains "$PTY_OUT" "slow1"
  check "final summary still printed" contains "$PTY_OUT" "== summary =="
  PTY_OUT="$(run_pty "$HOSTS_CMD" --from par --no-local --no-sweep --no-status --no-progress || true)"
  check "--no-progress disables it" not_contains "$PTY_OUT" $'\033[?25l'
else
  echo "  skip - python3 が無いため端末表示のテストを省略"
fi

section "skip/warn lines of successful steps"
run --from warn --no-local -j 1
check "exit 0 (warnings do not fail)" rc_is 0
check "skip line shown" contains "$OUT" "[skip pull] dirty working tree"
check "repo header shown" contains "$OUT" "==> /repo/b"
check "step flagged" contains "$OUT" "[ok] pull（スキップ・警告あり）"
check "summary marks ok!" contains "$OUT" "ok!"
check "legend shown" contains "$OUT" "ok! = "
check "clean host not flagged" not_contains "$OUT" "==> /repo/a"
WARN_LOCAL=ghq-pull run --from alpha -H beta -j 1 --no-sweep --no-status
check "local skip line shown" contains "$OUT" "==> /repo/a"
run --from alpha --no-local -j 1
check "no warn legend when clean" not_contains "$OUT" "ok! = "

section "step selection"
run --from alpha --update --no-sweep --no-status -H beta --no-local
check "update only on beta" [ "$CALLS_OUT" = "beta ghq-update" ]
run --from alpha --no-pull --no-status --no-local -j 1
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
run --from mixed --no-local -j 1
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
printf 'alpha: Local\n' > "$WORK/private/ghq/hosts.local"
run --from alpha --dry-run
check "reserved host name 'local' rejected" rc_is 1
rm "$WORK/private/ghq/hosts.local"
mv "$WORK/private/ghq/hosts" "$WORK/private/ghq/hosts.bak"
run --from alpha --dry-run
check "missing declaration is an error" rc_is 1
mv "$WORK/private/ghq/hosts.bak" "$WORK/private/ghq/hosts"

echo
if [[ "$FAILURES" -ne 0 ]]; then echo "$FAILURES 件失敗" >&2; exit 1; fi
echo "すべて成功"
