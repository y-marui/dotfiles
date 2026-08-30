#!/usr/bin/env bash
# apply.sh
# ai/gemini/mcp/servers.json の定義を ~/.gemini/config/mcp_config.json に適用・更新する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/gemini/mcp/servers.json"
GEMINI_CONFIG_DIR="${HOME}/.gemini/config"
GEMINI_CONFIG="${GEMINI_CONFIG_DIR}/mcp_config.json"

PYTHON_BIN="python3"

if [[ ! -f "${SERVERS_FILE}" ]]; then
  echo "Error: ${SERVERS_FILE} not found." >&2
  exit 1
fi

mkdir -p "${GEMINI_CONFIG_DIR}"

"${PYTHON_BIN}" - "${SERVERS_FILE}" "${GEMINI_CONFIG}" "${DOTFILES_DIR}" << 'PYEOF'
import json
import os
import sys

servers_path, gemini_config_path, dotfiles_dir = sys.argv[1], sys.argv[2], sys.argv[3]

with open(servers_path, encoding="utf-8") as f:
    raw_servers = f.read().replace("${DOTFILES_DIR}", dotfiles_dir)
    declared_entries = json.loads(raw_servers)

gemini_data = {"mcpServers": {}}
if os.path.exists(gemini_config_path):
    try:
        with open(gemini_config_path, encoding="utf-8") as f:
            gemini_data = json.load(f)
            if "mcpServers" not in gemini_data:
                gemini_data["mcpServers"] = {}
    except (json.JSONDecodeError, PermissionError):
        gemini_data = {"mcpServers": {}}

mcp_servers = gemini_data["mcpServers"]

for entry in declared_entries:
    name = entry["name"]
    w_type = entry.get("type", "stdio")
    if w_type == "stdio":
        mcp_servers[name] = {
            "command": entry["command"],
            "args": entry.get("args", []),
        }
        if "env" in entry:
            mcp_servers[name]["env"] = entry["env"]
    elif w_type in {"http", "sse"}:
        mcp_servers[name] = {
            "serverUrl": entry["url"]
        }

with open(gemini_config_path, "w", encoding="utf-8") as f:
    json.dump(gemini_data, f, indent=2)
    f.write("\n")

print(f"Applied Gemini MCP configuration to {gemini_config_path}")
PYEOF
