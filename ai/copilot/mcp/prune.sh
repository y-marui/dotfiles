#!/usr/bin/env bash
# servers.json に記載のない Copilot CLI user scope MCP を削除する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/copilot/mcp/servers.json"

command -v copilot >/dev/null 2>&1 || {
  echo "Error: copilot CLI is not installed." >&2
  exit 1
}

python3 - "${SERVERS_FILE}" <<'PYEOF'
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

servers_path = sys.argv[1]
with open(servers_path, encoding="utf-8") as file:
    declared = {entry["name"] for entry in json.load(file)}

result = subprocess.run(
    ["copilot", "mcp", "list", "--json"],
    capture_output=True,
    check=True,
    text=True,
)
actual = json.loads(result.stdout).get("mcpServers", {})
remove_names = sorted(
    name
    for name, entry in actual.items()
    if entry.get("source") == "user" and name not in declared
)
if not remove_names:
    print("  (nothing to prune)")
    raise SystemExit(0)

config_path = Path.home() / ".copilot" / "mcp-config.json"
if config_path.exists():
    backup_path = (
        Path.home()
        / ".dotfiles-backup"
        / datetime.now().strftime("%Y%m%d%H%M%S")
        / "copilot-mcp-pruned"
        / "mcp-config.json"
    )
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_path, backup_path)
    print(f"  backup  {backup_path}")

for name in remove_names:
    print(f"  remove  {name}")
    subprocess.run(["copilot", "mcp", "remove", name], check=True)
PYEOF
