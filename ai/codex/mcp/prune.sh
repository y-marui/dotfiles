#!/usr/bin/env bash
# servers.json 未記載の直接登録 MCP を削除する。plugin/app 由来は保持する。

set -euo pipefail
umask 077

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/codex/mcp/servers.json"

actual_file="$(mktemp)"
plugins_file="$(mktemp)"
trap 'rm -f "${actual_file}" "${plugins_file}"' EXIT
codex mcp list --json > "${actual_file}"
codex plugin list --json > "${plugins_file}"

python3 - "${SERVERS_FILE}" "${actual_file}" "${plugins_file}" <<'PYEOF'
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

servers_path, actual_path, plugins_path = sys.argv[1:]
with open(servers_path, encoding="utf-8") as file:
    declared = {entry["name"] for entry in json.load(file)}
with open(actual_path, encoding="utf-8") as file:
    actual = {entry["name"]: entry for entry in json.load(file)}
with open(plugins_path, encoding="utf-8") as file:
    plugins = json.load(file).get("installed", [])

plugin_owned = set()
for plugin in plugins:
    source_path = plugin.get("source", {}).get("path")
    if not plugin.get("installed", True) or not source_path:
        continue
    try:
        with (Path(source_path) / ".mcp.json").open(encoding="utf-8") as file:
            plugin_owned.update(json.load(file).get("mcpServers", {}))
    except (FileNotFoundError, PermissionError, json.JSONDecodeError):
        pass


def is_app_owned(entry):
    return entry.get("transport", {}).get("command", "").startswith(
        "/Applications/ChatGPT.app/"
    )


def is_loopback(entry):
    hostname = urlparse(entry.get("transport", {}).get("url", "")).hostname
    return hostname in {"127.0.0.1", "localhost", "::1"}


remove_names = sorted(
    name
    for name, entry in actual.items()
    if name not in declared
    and name not in plugin_owned
    and not is_app_owned(entry)
    and not is_loopback(entry)
)
if not remove_names:
    print("  (nothing to prune)")
    raise SystemExit(0)

config_path = (
    Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
    / "config.toml"
)
if config_path.exists():
    backup_path = (
        Path.home()
        / ".dotfiles-backup"
        / datetime.now().strftime("%Y%m%d%H%M%S")
        / "codex-mcp-pruned"
        / "config.toml"
    )
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_path, backup_path)
    print(f"  backup  {backup_path}")

for name in remove_names:
    print(f"  remove  {name}")
    subprocess.run(["codex", "mcp", "remove", name], check=True)
PYEOF
