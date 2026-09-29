#!/usr/bin/env bash
# Codex plugin の差分・削除ロジックを偽の app-server で検証する。
# 実際の Codex plugin 状態やネットワークには影響しない。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIFF="$REPO/ai/codex/plugin/diff.sh"
WORK="$(mktemp -d)"
FAILURES=0

trap 'rm -rf "$WORK"' EXIT

ROOT="$WORK/dotfiles"
STUBS="$WORK/stubs"
STATE="$WORK/state"
PLUGINS_FILE="$ROOT/ai/codex/plugin/plugins.json"
mkdir -p "$(dirname "$PLUGINS_FILE")" "$STUBS" "$STATE"

cat > "$STUBS/codex" <<'STUB'
#!/usr/bin/env python3
import json
import os
import sys

log_path = os.environ["FAKE_CODEX_LOG"]


def log(message):
    with open(log_path, "a", encoding="utf-8") as file:
        file.write(message + "\n")


if sys.argv[1:] != ["app-server"]:
    log(" ".join(sys.argv[1:]))
    raise SystemExit(0)

plugins = [
    {
        "id": "work-pets@openai-curated-remote",
        "name": "work-pets",
        "source": {"type": "remote"},
        "installed": True,
        "installPolicy": "INSTALLED_BY_DEFAULT",
    },
    {
        "id": "user-remote@openai-curated-remote",
        "name": "user-remote",
        "source": {"type": "remote"},
        "installed": True,
        "installPolicy": "AVAILABLE",
    },
    {
        "id": "local-default@openai-bundled",
        "name": "local-default",
        "source": {"type": "local"},
        "installed": True,
        "installPolicy": "INSTALLED_BY_DEFAULT",
    },
]

for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message:
        continue
    method = message["method"]
    if method == "plugin/list":
        result = {
            "marketplaceLoadErrors": [],
            "marketplaces": [
                {"name": "fixture-marketplace", "plugins": plugins},
            ],
        }
    elif method == "plugin/uninstall":
        log(f"plugin/uninstall {message['params']['pluginId']}")
        result = {}
    elif method == "plugin/install":
        log(f"plugin/install {message['params']['pluginName']}")
        result = {}
    else:
        result = {}
    print(json.dumps({"id": message["id"], "result": result}), flush=True)
STUB
chmod +x "$STUBS/codex"

export FAKE_CODEX_LOG="$STATE/codex.log"
export PATH="$STUBS:$PATH"

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

run_diff() {
  RC=0
  OUTPUT="$(DOTFILES_DIR="$ROOT" bash "$DIFF" "$@" 2>&1)" || RC=$?
}

printf '{"plugins": []}\n' > "$PLUGINS_FILE"
run_diff
check "unmanaged remote plugin is reported" contains "$OUTPUT" "[+actual]  user-remote@openai-curated-remote"
check "local plugin remains tracked even with the default policy" contains "$OUTPUT" "[+actual]  local-default@openai-bundled"
check "remote default plugin is omitted from diff" not_contains "$OUTPUT" "work-pets@openai-curated-remote"
check "diff exits 1 for tracked differences" test "$RC" -eq 1

run_diff --summary
check "summary excludes the remote default plugin" test "$OUTPUT" = "+2 actual のみ"
check "summary exits 1 for tracked differences" test "$RC" -eq 1

printf '%s\n' '{' '  "plugins": [' '    "local-default@openai-bundled",' '    "user-remote@openai-curated-remote",' '    "work-pets@openai-curated-remote"' '  ]' '}' > "$PLUGINS_FILE"
run_diff
check "declared remote default plugin is outside comparison" contains "$OUTPUT" "No diff:"
check "matching tracked plugins exit 0" test "$RC" -eq 0

printf '{"plugins": []}\n' > "$PLUGINS_FILE"
: > "$FAKE_CODEX_LOG"
run_diff prune
calls="$(cat "$FAKE_CODEX_LOG")"
check "prune removes an undeclared user remote plugin" contains "$calls" "plugin/uninstall user-remote@openai-curated-remote"
check "prune removes an undeclared local plugin" contains "$calls" "plugin remove local-default@openai-bundled"
check "prune does not remove a remote default plugin" not_contains "$calls" "work-pets@openai-curated-remote"
check "prune exits 0" test "$RC" -eq 0

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
