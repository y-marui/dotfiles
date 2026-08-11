#!/usr/bin/env bash
# cache.sh
# ~/.claude.json の user scope mcpServers を servers.cache.json に記録する
#
# 動作:
#   ヘッダーの値（トークン等のシークレット）は絶対に書き出さず、
#   キー名の有無だけを記録する。
#
# 使い方:
#   bash ai/claude/mcp/cache.sh
#   dots claude cache --mcp-only

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CACHE_FILE="$DOTFILES_DIR/ai/claude/mcp/servers.cache.json"

python3 - "$CACHE_FILE" << 'PYEOF'
import json
import os
import sys

cache_path = sys.argv[1]
claude_json_path = os.path.expanduser("~/.claude.json")

try:
    with open(claude_json_path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}

servers = data.get("mcpServers", {})
out = {}
for name, cfg in servers.items():
    entry = {"type": cfg.get("type", "stdio")}
    if entry["type"] == "stdio":
        entry["command"] = cfg.get("command")
        entry["args"] = cfg.get("args", [])
    else:
        entry["url"] = cfg.get("url")
        headers = cfg.get("headers") or {}
        if headers:
            # 値は絶対に書き出さない。キー名の有無のみ記録する。
            entry["headerKeys"] = sorted(headers.keys())
    out[name] = entry

with open(cache_path, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False, sort_keys=True)
    f.write("\n")

print(f"servers.cache.json updated: {len(out)} server(s).")
PYEOF
