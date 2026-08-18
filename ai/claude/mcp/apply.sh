#!/usr/bin/env bash
# apply.sh
# servers.json にあって未登録の MCP サーバーを `claude mcp add -s user` で追加する
#
# 動作:
#   1. ~/.claude.json を直接読み、servers.json と異なる user scope 登録を追加・更新
#   2. 未宣言のサーバー（IDE・Claude.app等が動的に追加した分）は削除しない
#   3. ヘッダーの値（シークレット）は cmd で都度生成し、コマンドラインには表示しない
#
# 使い方:
#   bash ai/claude/mcp/apply.sh
#   dots claude apply --mcp-only

set -euo pipefail
umask 077

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="$DOTFILES_DIR/ai/claude/mcp/servers.json"
CLAUDE_JSON="$HOME/.claude.json"

echo "==> Adding missing MCP servers from servers.json..."
python3 - "$SERVERS_FILE" "$CLAUDE_JSON" << 'PYEOF'
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

servers_path, claude_json_path = sys.argv[1], sys.argv[2]

with open(servers_path, encoding="utf-8") as f:
    declared = json.load(f)

try:
    with open(claude_json_path, encoding="utf-8") as f:
        actual = json.load(f).get("mcpServers", {})
except FileNotFoundError:
    actual = {}

config_path = Path(claude_json_path)
mode_changed = False
if config_path.exists() and config_path.stat().st_mode & 0o077:
    os.chmod(config_path, 0o600)
    mode_changed = True
    print(f"  chmod 600  {config_path}")

resolved_headers = {}
for entry in declared:
    headers = {}
    for header_name, spec in entry.get("headers", {}).items():
        resolved = subprocess.run(
            spec["cmd"], capture_output=True, text=True, check=True
        ).stdout.strip()
        if not resolved:
            raise RuntimeError(f"Credential command returned an empty value: {header_name}")
        headers[header_name] = spec.get("prefix", "") + resolved
    resolved_headers[entry["name"]] = headers


def matches(entry, current):
    if entry["type"] == "stdio":
        return (
            current.get("type", "stdio") == "stdio"
            and current.get("command") == entry["command"]
            and current.get("args", []) == entry.get("args", [])
        )
    return (
        current.get("type") in {"http", "sse"}
        and current.get("url") == entry["url"]
        and current.get("headers", {}) == resolved_headers[entry["name"]]
    )


changed_entries = [
    entry for entry in declared if not matches(entry, actual.get(entry["name"], {}))
]
if not changed_entries:
    if not mode_changed:
        print("  (already up to date)")
    sys.exit(0)

if config_path.exists():
    backup_path = (
        Path.home()
        / ".dotfiles-backup"
        / datetime.now().strftime("%Y%m%d%H%M%S")
        / "claude-mcp"
        / "config.json"
    )
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_path, backup_path)
    print(f"  backup  {backup_path}")

for entry in changed_entries:
    name = entry["name"]
    if name in actual:
        print(f"  replace  {name}")
        subprocess.run(
            ["claude", "mcp", "remove", "-s", "user", name],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    else:
        print(f"  add  {name}")
    cmd = ["claude", "mcp", "add", "-s", "user"]

    if entry["type"] == "stdio":
        cmd += [name, "--", entry["command"], *entry.get("args", [])]
    else:
        cmd += ["--transport", "http", name, entry["url"]]
        for header_name, value in resolved_headers[name].items():
            cmd += ["-H", f"{header_name}: {value}"]

    # secret を含みうるため cmd 自体は表示しない
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)

if config_path.exists():
    os.chmod(config_path, 0o600)
PYEOF
