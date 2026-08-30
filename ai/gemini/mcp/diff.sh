#!/usr/bin/env bash
# diff.sh
# ~/.gemini/config/mcp_config.json と ai/gemini/mcp/servers.json の差分を表示する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/gemini/mcp/servers.json"
GEMINI_CONFIG="${HOME}/.gemini/config/mcp_config.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

PYTHON_BIN="python3"

if [[ ! -f "${SERVERS_FILE}" ]]; then
  echo "Error: ${SERVERS_FILE} not found." >&2
  exit 1
fi

"${PYTHON_BIN}" - "${SERVERS_FILE}" "${GEMINI_CONFIG}" "${SUMMARY_MODE}" "${DOTFILES_DIR}" << 'PYEOF'
import json
import os
import sys

servers_path, gemini_config_path, summary_mode, dotfiles_dir = (
    sys.argv[1],
    sys.argv[2],
    sys.argv[3] == "1",
    sys.argv[4],
)

with open(servers_path, encoding="utf-8") as f:
    raw_servers = f.read().replace("${DOTFILES_DIR}", dotfiles_dir)
    declared_entries = json.loads(raw_servers)

declared = {entry["name"]: entry for entry in declared_entries}

actual_config = {}
if os.path.exists(gemini_config_path):
    try:
        with open(gemini_config_path, encoding="utf-8") as f:
            gemini_json = json.load(f)
            actual_config = gemini_json.get("mcpServers", {})
    except (json.JSONDecodeError, PermissionError):
        pass

actual_keys = set(actual_config.keys())
declared_keys = set(declared.keys())

only_in_actual = sorted(actual_keys - declared_keys)
only_in_files = sorted(declared_keys - actual_keys)


def config_matches(wanted, current):
    w_type = wanted.get("type", "stdio")
    if w_type == "stdio":
        return (
            current.get("command") == wanted.get("command")
            and current.get("args", []) == wanted.get("args", [])
        )
    elif w_type in {"http", "sse"}:
        return current.get("serverUrl") == wanted.get("url") or current.get("url") == wanted.get("url")
    return False


mismatched = sorted(
    name
    for name in declared_keys & actual_keys
    if not config_matches(declared[name], actual_config[name])
)

if summary_mode:
    parts = []
    if only_in_actual:
        parts.append(f"+{len(only_in_actual)} actual のみ")
    if only_in_files:
        parts.append(f"-{len(only_in_files)} files のみ")
    if mismatched:
        parts.append(f"~{len(mismatched)} config 不一致")
    if parts:
        print(" / ".join(parts))
    sys.exit(0)

if not only_in_actual and not only_in_files and not mismatched:
    print("No diff: Gemini/Antigravity の MCP 登録状態と servers.json は一致しています。")
else:
    if only_in_actual:
        print("~/.gemini/config/mcp_config.json に登録済みだが servers.json 未記載 (+actual のみ):")
        for name in only_in_actual:
            print(f"  [+actual]  {name}")
        print()
    if only_in_files:
        print("servers.json にあるが ~/.gemini/config/mcp_config.json 未登録 (-files のみ):")
        for name in only_in_files:
            print(f"  [-files]  {name}")
        print()
    if mismatched:
        print("同名だが設定が不一致 (~config):")
        for name in mismatched:
            print(f"  [~config]  {name}")
        print()

sys.exit(1 if only_in_actual or only_in_files or mismatched else 0)
PYEOF
