#!/usr/bin/env bash
# plugins.json 未記載の Codex plugin を削除する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/codex/plugin/plugins.json"

python3 - "${PLUGINS_FILE}" <<'PYEOF'
import json
import subprocess
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    declared = set(json.load(file).get("plugins", []))
result = subprocess.run(
    ["codex", "plugin", "list", "--json"],
    capture_output=True,
    check=True,
    text=True,
)
actual = {
    entry["pluginId"]
    for entry in json.loads(result.stdout).get("installed", [])
    if entry.get("installed", True)
}
remove_names = sorted(actual - declared)
if not remove_names:
    print("  (nothing to prune)")
    raise SystemExit(0)
for name in remove_names:
    print(f"  remove  {name}")
    subprocess.run(["codex", "plugin", "remove", name], check=True)
PYEOF
