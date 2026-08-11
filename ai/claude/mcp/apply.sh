#!/usr/bin/env bash
# apply.sh
# servers.json にあって未登録の MCP サーバーを `claude mcp add -s user` で追加する
#
# 動作:
#   1. ~/.claude.json を直接読み、servers.json にあってキャッシュにないものだけを追加（常に user scope）
#   2. 未宣言のサーバー（IDE・Claude.app等が動的に追加した分）は削除しない
#   3. ヘッダーの値（シークレット）は cmd で都度生成し、ファイルには書き出さない
#
# 使い方:
#   bash ai/claude/mcp/apply.sh
#   dots claude apply --mcp-only

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="$DOTFILES_DIR/ai/claude/mcp/servers.json"
CLAUDE_JSON="$HOME/.claude.json"

echo "==> Adding missing MCP servers from servers.json..."
python3 - "$SERVERS_FILE" "$CLAUDE_JSON" << 'PYEOF'
import json
import subprocess
import sys

servers_path, claude_json_path = sys.argv[1], sys.argv[2]

with open(servers_path, encoding="utf-8") as f:
    declared = json.load(f)

try:
    with open(claude_json_path, encoding="utf-8") as f:
        actual_names = set(json.load(f).get("mcpServers", {}).keys())
except FileNotFoundError:
    actual_names = set()

missing = [entry for entry in declared if entry["name"] not in actual_names]

if not missing:
    print("  (already up to date)")
    sys.exit(0)

for entry in missing:
    name = entry["name"]
    cmd = ["claude", "mcp", "add", "-s", "user"]

    if entry["type"] == "stdio":
        cmd += [name, "--", entry["command"], *entry.get("args", [])]
    else:
        cmd += ["--transport", "http", name, entry["url"]]
        for header_name, spec in entry.get("headers", {}).items():
            resolved = subprocess.run(
                spec["cmd"], capture_output=True, text=True, check=True
            ).stdout.strip()
            value = spec.get("prefix", "") + resolved
            cmd += ["-H", f"{header_name}: {value}"]

    print(f"  add  {name}")
    # secret を含みうるため cmd 自体は表示しない
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
PYEOF
