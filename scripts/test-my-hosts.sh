#!/usr/bin/env bash
# bin/unix/my-hosts の回帰テスト。ssh と ghq-* は偽のコマンドに差し替えるため、
# 実際のホスト・リポジトリには一切影響しない。
set -euo pipefail

HOSTS_CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/my-hosts"
WORK="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/private/hosts"
export DOTFILES_PRIVATE_DIR="$WORK/private"
export MY_HOSTS_LOG_DIR="$WORK/logs"
export CALLS="$WORK/calls"

for c in ghq-pull ghq-update ghq-sweep ghq-status install-my-apps; do
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
[[ "$host" == winhost && "$*" == install-my-apps* ]] && { echo "install-my-apps は macOS 専用です" >&2; exit 64; }
[[ "$host" == warngit && "$*" == ghq-sweep ]] && { echo "==> /repo/c"; echo "warning: could not fast-forward x (diverged)." >&2; }
echo "remote-out $host $*"
STUB
chmod +x "$WORK/ssh"
export MY_HOSTS_SSH="$WORK/ssh"
export PATH="$WORK/bin:$PATH"

cat > "$WORK/private/hosts/hosts" <<'DECL'
# コメント
Alpha:  beta gamma   # 行末コメント
beta:   gamma
gamma:  beta
mixed:  beta down badsweep gamma
par:    slow1 slow2
warn:   warnhost beta
warng:  warngit
wins:   winhost beta
winsk:  winhost:windows beta
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
check "lists remote command" contains "$OUT" "BatchMode=yes -o ConnectTimeout=5 beta ghq-sweep"
check "lists local command" contains "$OUT" "would run: ghq-sweep"
check "nothing executed" test ! -s "$CALLS"

section "default steps and order (case-insensitive --from)"
run --from ALPHA -j 1
check "exit 0" rc_is 0
expected="local ghq-sweep
local ghq-status
beta ghq-sweep
beta ghq-status
gamma ghq-sweep
gamma ghq-status"
check "call order" [ "$CALLS_OUT" = "$expected" ]
check "summary shown" contains "$OUT" "== summary =="
check "success output hidden" not_contains "$OUT" "remote-out beta ghq-sweep"
check "status output shown" contains "$OUT" "remote-out beta ghq-status"
check "log written" test -f "$MY_HOSTS_LOG_DIR/beta.log"

section "parallel hosts"
start=$SECONDS
run pull --no-status --from par --no-local
elapsed=$((SECONDS - start))
check "exit 0" rc_is 0
check "hosts run concurrently (2s sleeps finish well under 4s)" test "$elapsed" -lt 4
check "both hosts ran" contains "$CALLS_OUT" "slow2 ghq-pull"
in_order() { [[ "$1" == *"==> slow1"*"==> slow2"* ]]; }
check "output kept in declared order" in_order "$OUT"
start=$SECONDS
run pull --no-status --from par --no-local -j 1
elapsed=$((SECONDS - start))
check "-j 1 is sequential (>= 4s)" test "$elapsed" -ge 4
run --from par --no-local -j 0
check "invalid --jobs rejected" rc_is 1

section "progress display"
run pull --no-status --from par --no-local
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
  PTY_OUT="$(run_pty "$HOSTS_CMD" pull --no-status --from par --no-local || true)"
  check "progress drawn on a terminal" contains "$PTY_OUT" $'\033[?25l'
  check "cursor restored" contains "$PTY_OUT" $'\033[?25h'
  check "host shown in progress" contains "$PTY_OUT" "slow1"
  check "final summary still printed" contains "$PTY_OUT" "== summary =="
  PTY_OUT="$(run_pty "$HOSTS_CMD" pull --no-status --from par --no-local --no-progress || true)"
  check "--no-progress disables it" not_contains "$PTY_OUT" $'\033[?25l'
else
  echo "  skip - python3 が無いため端末表示のテストを省略"
fi

section "skip/warn lines of successful steps"
run pull --from warn --no-local -j 1
check "exit 0 (warnings do not fail)" rc_is 0
check "skip line shown" contains "$OUT" "[skip pull] dirty working tree"
check "repo header shown" contains "$OUT" "==> /repo/b"
check "step flagged" contains "$OUT" "[ok] pull（スキップ・警告あり）"
check "summary marks ok!" contains "$OUT" "ok!"
check "legend shown" contains "$OUT" "ok! = "
check "clean host not flagged" not_contains "$OUT" "==> /repo/a"
WARN_LOCAL=ghq-pull run pull --no-status --from alpha -H beta -j 1
check "local skip line shown" contains "$OUT" "==> /repo/a"
run --from alpha --no-local -j 1
check "no warn legend when clean" not_contains "$OUT" "ok! = "

section "warning: lines are surfaced"
run sweep --from warng --no-local -j 1 --no-status
check "warning line shown" contains "$OUT" "warning: could not fast-forward x (diverged)."
check "repo header shown for warning" contains "$OUT" "==> /repo/c"
check "step flagged for warning" contains "$OUT" "[ok] sweep（スキップ・警告あり）"
check "exit 0 for warning" rc_is 0

section "step selection (subcommands)"
run status --from alpha --no-local -j 1
check "status runs status only" [ "$CALLS_OUT" = "beta ghq-status
gamma ghq-status" ]
run status -a --from alpha --no-local -H gamma
check "status -a passed" [ "$CALLS_OUT" = "gamma ghq-status -a" ]
run pull --from alpha --no-local -H beta
check "pull is pull then status" [ "$CALLS_OUT" = "beta ghq-pull
beta ghq-status" ]
run pull --no-status --from alpha --no-local -H beta
check "pull --no-status is pull only" [ "$CALLS_OUT" = "beta ghq-pull" ]
run sweep --from alpha --no-local -H beta
check "sweep is sweep then status" [ "$CALLS_OUT" = "beta ghq-sweep
beta ghq-status" ]
run sweep --no-status --from alpha --no-local -j 1
check "sweep --no-status is sweep only" [ "$CALLS_OUT" = "beta ghq-sweep
gamma ghq-sweep" ]
run update --from alpha --no-local -H beta
check "update is pull, update --sync-only, status" [ "$CALLS_OUT" = "beta ghq-pull
beta ghq-update --sync-only
beta ghq-status" ]
run update --no-status --from alpha --no-local -H beta
check "update --no-status" [ "$CALLS_OUT" = "beta ghq-pull
beta ghq-update --sync-only" ]
run status --no-status --from alpha
check "status --no-status is an error" rc_is 1
run --update --from alpha
check "removed --update is rejected" rc_is 1
run --only --from alpha
check "removed --only is rejected" rc_is 1
run --no-pull --from alpha
check "removed --no-pull is rejected" rc_is 1

section "filter pass-through"
run pull -f 'a|b' --from alpha --no-local -H beta
check "filter passed to ghq-pull (single-quoted)" [ "$CALLS_OUT" = "beta ghq-pull -f 'a|b'
beta ghq-status -f 'a|b'" ]
run pull -f "it's" --from alpha --no-local -H beta
check "filter with a single quote rejected" rc_is 1
run update --filter x --from alpha --no-local -H beta --no-status
check "filter passed to ghq-update" contains "$CALLS_OUT" "beta ghq-update --sync-only -f x"
run pull -f x --from alpha -H beta
check "local gets filter too" contains "$CALLS_OUT" "local ghq-pull -f x"
run pull -f
check "-f needs an argument" rc_is 1

section "host selection"
run --from beta
check "beta targets gamma only (no alpha)" not_contains "$CALLS_OUT" "Alpha"
check "gamma reached" contains "$CALLS_OUT" "gamma ghq-sweep"
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
check "unreachable host stops its own steps" not_contains "$CALLS_OUT" "down ghq-status"
check "failure output shown" contains "$OUT" "sweep broke"
check "summary marks ssh failure" contains "$OUT" "ssh"
check "summary marks skip" contains "$OUT" "skip"
FAIL_LOCAL=ghq-sweep run --from alpha -H beta
check "local failure exits 1" rc_is 1
check "remote still ran after local failure" contains "$CALLS_OUT" "beta ghq-status"

section "apps"
run apps --from alpha -H beta -j 1
check "apps runs install-my-apps --no-gui remotely, no status" [ "$CALLS_OUT" = "local install-my-apps
beta install-my-apps --no-gui" ]
check "apps summary has no status column" not_contains "$OUT" "status"
run apps --from alpha -H beta -j 1 -- -f "My App"
check "apps args forwarded and quoted" [ "$CALLS_OUT" = "local install-my-apps -f My App
beta install-my-apps --no-gui -f 'My App'" ]
run apps --from alpha --no-local -H beta -- "it's"
check "apps arg with a single quote rejected" rc_is 1
run apps --from wins --no-local -j 1
check "apps exit 64 is a skip, not a failure" rc_is 0
check "apps skip shown" contains "$OUT" "[skip] apps"
check "other hosts still ran after skip" contains "$CALLS_OUT" "beta install-my-apps --no-gui"
run pull --from wins --no-local -j 1
check "non-apps steps unaffected" rc_is 0
run apps --from alpha --no-local -H beta --dry-run
check "apps dry-run" contains "$OUT" "beta install-my-apps --no-gui"
run apps --from alpha -f x
check "apps rejects --filter" rc_is 1
run pull --from alpha -- -f
check "-- rejected outside apps" rc_is 1
run apps --from alpha --no-status --no-local -H beta
check "apps ignores --no-status" rc_is 0

section "windows host (:windows) skips fetch steps (#107)"
run pull --from winsk --no-local -j 1
check "skip is not a failure" rc_is 0
check "pull not sent to windows host" not_contains "$CALLS_OUT" "winhost ghq-pull"
check "status still runs on windows host" contains "$CALLS_OUT" "winhost ghq-status"
check "other hosts still pulled" contains "$CALLS_OUT" "beta ghq-pull"
check "skip notice names the reason" contains "$OUT" "[skip] pull: Windows では GitHub 認証が未対応"
for sub in sweep update; do
  run "$sub" --from winsk --no-local -H winhost
  check "$sub skipped on windows host" not_contains "$CALLS_OUT" "winhost ghq-$sub"
  check "$sub skip exits 0" rc_is 0
done
run apps --from winsk --no-local -H winhost
check "apps still runs on windows host" contains "$CALLS_OUT" "winhost install-my-apps --no-gui"
run pull --from winsk --no-local -H winhost --dry-run
check "dry-run shows skip" contains "$OUT" "would skip: pull"
check "-H accepts name without :windows" rc_is 0

section "hosts.local and errors"
printf 'alpha: extra\n' > "$WORK/private/hosts/hosts.local"
run --from alpha --dry-run --no-local
check "hosts.local additive" contains "$OUT" "extra"
rm "$WORK/private/hosts/hosts.local"
printf 'alpha: -oProxyCommand=x\n' > "$WORK/private/hosts/hosts.local"
run --from alpha --dry-run
check "option-like host rejected" rc_is 1
rm "$WORK/private/hosts/hosts.local"
printf 'alpha: Local\n' > "$WORK/private/hosts/hosts.local"
run --from alpha --dry-run
check "reserved host name 'local' rejected" rc_is 1
rm "$WORK/private/hosts/hosts.local"
mv "$WORK/private/hosts/hosts" "$WORK/private/hosts/hosts.bak"
run --from alpha --dry-run
check "missing declaration is an error" rc_is 1
mv "$WORK/private/hosts/hosts.bak" "$WORK/private/hosts/hosts"

echo
if [[ "$FAILURES" -ne 0 ]]; then echo "$FAILURES 件失敗" >&2; exit 1; fi
echo "すべて成功"
