#!/usr/bin/env bash
# servers.json にある Copilot CLI user scope MCP を追加・更新する。

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
    declared = json.load(file)

result = subprocess.run(
    ["copilot", "mcp", "list", "--json"],
    capture_output=True,
    check=True,
    text=True,
)
actual = {
    name: entry
    for name, entry in json.loads(result.stdout).get("mcpServers", {}).items()
    if entry.get("source") == "user"
}
config_path = Path.home() / ".copilot" / "mcp-config.json"
backup_path = (
    Path.home()
    / ".dotfiles-backup"
    / datetime.now().strftime("%Y%m%d%H%M%S")
    / "copilot-mcp"
    / "mcp-config.json"
)
backup_created = False


def matches(wanted, current):
    return (
        current.get("type") == wanted["type"]
        and current.get("command") == wanted.get("command")
        and current.get("args", []) == wanted.get("args", [])
        and current.get("tools", ["*"]) == wanted.get("tools", ["*"])
    )


def backup_config():
    global backup_created
    if backup_created or not config_path.exists():
        return
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_path, backup_path)
    backup_created = True


changed = False
for entry in declared:
    name = entry["name"]
    current = actual.get(name)
    if current and matches(entry, current):
        continue
    if current:
        backup_config()
        print(f"  replace  {name}")
        subprocess.run(["copilot", "mcp", "remove", name], check=True)
    else:
        print(f"  add  {name}")

    command = ["copilot", "mcp", "add", name]
    for tool in entry.get("tools", ["*"]):
        command.extend(["--tools", tool])
    command.extend(["--", entry["command"], *entry.get("args", [])])
    subprocess.run(command, check=True)
    changed = True

if not changed:
    print("  (already up to date)")
elif backup_created:
    print(f"  backup  {backup_path}")
PYEOF
