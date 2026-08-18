#!/usr/bin/env bash
# servers.json 未記載の user scope MCP を削除する。loopback app MCP は保持する。

set -euo pipefail
umask 077

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/claude/mcp/servers.json"
CLAUDE_JSON="${HOME}/.claude.json"

python3 - "${SERVERS_FILE}" "${CLAUDE_JSON}" <<'PYEOF'
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

servers_path, claude_path = sys.argv[1:]
with open(servers_path, encoding="utf-8") as file:
    declared = {entry["name"] for entry in json.load(file)}
try:
    with open(claude_path, encoding="utf-8") as file:
        config = json.load(file)
except FileNotFoundError:
    print("  (nothing to prune)")
    raise SystemExit(0)


def is_local_app(entry):
    return urlparse(entry.get("url", "")).hostname in {"127.0.0.1", "localhost", "::1"}


actual = config.get("mcpServers", {})
remove_names = sorted(
    name for name, entry in actual.items() if name not in declared and not is_local_app(entry)
)
if not remove_names:
    print("  (nothing to prune)")
    raise SystemExit(0)

backup_path = (
    Path.home()
    / ".dotfiles-backup"
    / datetime.now().strftime("%Y%m%d%H%M%S")
    / "claude-mcp-pruned.json"
)
backup_path.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(claude_path, backup_path)
print(f"  backup  {backup_path}")

for name in remove_names:
    print(f"  remove  {name}")
    subprocess.run(["claude", "mcp", "remove", "-s", "user", name], check=True)
os.chmod(claude_path, 0o600)
PYEOF
