#!/usr/bin/env bash
# plugins.json にあって未導入の Codex plugin を追加する。未宣言 plugin は削除しない。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/codex/plugin/plugins.json"

echo "==> Adding missing plugins from plugins.json..."
python3 - "${PLUGINS_FILE}" <<'PYEOF'
import json
import subprocess
import sys

plugins_path = sys.argv[1]

with open(plugins_path, encoding="utf-8") as file:
    declared = json.load(file).get("plugins", [])

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
missing = [plugin for plugin in declared if plugin not in actual]

if not missing:
    print("  (already up to date)")
    raise SystemExit(0)

for plugin in missing:
    print(f"  install  {plugin}")
    subprocess.run(
        ["codex", "plugin", "add", plugin],
        check=True,
        stdout=subprocess.DEVNULL,
    )
PYEOF
