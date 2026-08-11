#!/usr/bin/env bash
# diff.sh
# ~/.claude.json と既知 project の .mcp.json にある MCP 実態を検査する。
#
# ~/.claude.json を直接読むだけの軽量な処理（0.2秒程度）なので cache は持たない。
# claude CLI 経由か Claude.app（GUI）経由かを問わず、実際に登録されているものを検知できる。
#
# 動作:
#   [+actual] name  → user scope に登録済みだが servers.json 未記載
#   [+local] name   → local scope に登録済み（~/.claude.json の projects 配下）
#   [+project] name → project scope に登録済み（.mcp.json）
#   [-files]  name  → servers.json にあるがシステム未登録（dots claude apply --mcp-only で追加できる）
#
# 使い方:
#   bash ai/claude/mcp/diff.sh           # 差分を詳細表示
#   bash ai/claude/mcp/diff.sh --summary # 1行サマリーのみ出力
#
# ~/.claude.json または servers.json が見つからない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="$DOTFILES_DIR/ai/claude/mcp/servers.json"
CLAUDE_JSON="$HOME/.claude.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$CLAUDE_JSON" || ! -f "$SERVERS_FILE" ]]; then
  exit 1
fi

python3 - "$SERVERS_FILE" "$CLAUDE_JSON" "$SUMMARY_MODE" << 'PYEOF'
import json
import sys

servers_path, claude_json_path, summary_mode = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(servers_path, encoding="utf-8") as f:
    declared = {entry["name"] for entry in json.load(f)}

with open(claude_json_path, encoding="utf-8") as f:
    claude_config = json.load(f)

actual = set(claude_config.get("mcpServers", {}).keys())


def transport_name(config):
    if config.get("type") in {"http", "sse", "ws"} or "url" in config:
        return config.get("type", "http")
    return "stdio"


scoped_actual = []
for project_path, project_config in claude_config.get("projects", {}).items():
    for name, config in project_config.get("mcpServers", {}).items():
        scoped_actual.append(("local", project_path, name, transport_name(config)))

    project_mcp_path = f"{project_path}/.mcp.json"
    try:
        with open(project_mcp_path, encoding="utf-8") as f:
            project_mcp = json.load(f)
    except (FileNotFoundError, NotADirectoryError, PermissionError, json.JSONDecodeError):
        continue
    for name, config in project_mcp.get("mcpServers", {}).items():
        scoped_actual.append(("project", project_path, name, transport_name(config)))

only_in_actual = sorted(actual - declared)
only_in_files = sorted(declared - actual)

if summary_mode:
    parts = []
    actual_count = len(only_in_actual) + len(scoped_actual)
    if actual_count:
        parts.append(f"+{actual_count} actual のみ")
    if only_in_files:
        parts.append(f"-{len(only_in_files)} files のみ")
    if parts:
        print(" / ".join(parts))
    sys.exit(0)

if not only_in_actual and not only_in_files and not scoped_actual:
    print("No diff: 実際の登録状態と servers.json は一致しています。")
    sys.exit(0)

if only_in_actual:
    print("user scope に登録済みだが servers.json 未記載 (+actual のみ):")
    for name in only_in_actual:
        print(f"  [+actual]  {name}")
    print()
if scoped_actual:
    print("local / project scope にある追加登録 (+actual のみ):")
    for scope, project_path, name, transport in sorted(scoped_actual):
        print(f"  [+{scope}]  {name} ({transport}) @ {project_path}")
    print()
if only_in_files:
    print("servers.json にあるがシステム未登録 (-files のみ):")
    for name in only_in_files:
        print(f"  [-files]  {name}")

sys.exit(1)
PYEOF
