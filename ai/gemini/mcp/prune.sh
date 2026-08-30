#!/usr/bin/env bash
# prune.sh
# servers.json に記載のない ~/.gemini/config/mcp_config.json の定義を削除する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/gemini/mcp/servers.json"
GEMINI_CONFIG="${HOME}/.gemini/config/mcp_config.json"

PYTHON_BIN="python3"

if [[ ! -f "${GEMINI_CONFIG}" ]]; then
  echo "No Gemini MCP configuration file found."
  exit 0
fi

"${PYTHON_BIN}" - "${SERVERS_FILE}" "${GEMINI_CONFIG}" << 'PYEOF'
import json
import os
import sys

servers_path, gemini_config_path = sys.argv[1], sys.argv[2]

with open(servers_path, encoding="utf-8") as f:
    declared_entries = json.load(f)

declared_names = {entry["name"] for entry in declared_entries}

with open(gemini_config_path, encoding="utf-8") as f:
    gemini_data = json.load(f)

mcp_servers = gemini_data.get("mcpServers", {})
current_names = set(mcp_servers.keys())

to_remove = current_names - declared_names

if not to_remove:
    print("No unmanaged MCP servers to prune.")
    sys.exit(0)

for name in to_remove:
    print(f"Pruning unmanaged MCP server: {name}")
    del mcp_servers[name]

with open(gemini_config_path, "w", encoding="utf-8") as f:
    json.dump(gemini_data, f, indent=2)
    f.write("\n")

print("Pruned unmanaged MCP servers.")
PYEOF
