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
import os
import sys
from urllib.parse import urlparse

servers_path, claude_json_path, summary_mode = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(servers_path, encoding="utf-8") as f:
    declared_entries = json.load(f)
declared = {entry["name"]: entry for entry in declared_entries}

with open(claude_json_path, encoding="utf-8") as f:
    claude_config = json.load(f)
insecure_mode = os.stat(claude_json_path).st_mode & 0o077 != 0

actual_config = claude_config.get("mcpServers", {})
actual = set(actual_config)


def is_local_app(config):
    hostname = urlparse(config.get("url", "")).hostname
    return hostname in {"127.0.0.1", "localhost", "::1"}


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

extra_actual = actual - declared.keys()
app_actual = sorted(
    name for name in extra_actual if is_local_app(claude_config["mcpServers"][name])
)
only_in_actual = sorted(extra_actual - set(app_actual))
only_in_files = sorted(declared.keys() - actual)


def config_matches(wanted, current):
    if wanted["type"] == "stdio":
        return (
            current.get("type", "stdio") == "stdio"
            and current.get("command") == wanted["command"]
            and current.get("args", []) == wanted.get("args", [])
        )
    wanted_header_names = set(wanted.get("headers", {}))
    return (
        current.get("type") in {"http", "sse"}
        and current.get("url") == wanted["url"]
        and wanted_header_names == set(current.get("headers", {}))
    )


mismatched = sorted(
    name
    for name in declared.keys() & actual
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
    if insecure_mode:
        parts.append("~permission")
    if parts:
        print(" / ".join(parts))
    sys.exit(0)

if not only_in_actual and not only_in_files and not mismatched and not insecure_mode:
    print("No diff: 実際の登録状態と servers.json は一致しています。")
else:
    if only_in_actual:
        print("user scope に直接登録済みだが servers.json 未記載 (+actual のみ):")
        for name in only_in_actual:
            print(f"  [+actual]  {name}")
        print()
    if only_in_files:
        print("servers.json にあるがシステム未登録 (-files のみ):")
        for name in only_in_files:
            print(f"  [-files]  {name}")
        print()
    if mismatched:
        print("同名だが設定が不一致 (~config):")
        for name in mismatched:
            print(f"  [~config]  {name}")
        print()
    if insecure_mode:
        print("認証情報を含む設定ファイルの権限が広すぎます (~permission):")
        print("  [~permission]  ~/.claude.json (expected: 600)")
        print()

if app_actual:
    print("IDE/app が提供する loopback MCP (app 管理):")
    for name in app_actual:
        print(f"  [app]      {name}")
    print()
local_actual = [entry for entry in scoped_actual if entry[0] == "local"]
project_actual = [entry for entry in scoped_actual if entry[0] == "project"]
if local_actual:
    print("Claude Code local scope の MCP (端末・リポジトリ別、dotfiles 管理外):")
    for scope, project_path, name, transport in sorted(local_actual):
        print(f"  [+{scope}]  {name} ({transport}) @ {project_path}")
    print()
if project_actual:
    print("Claude Code project scope の MCP (.mcp.json、リポジトリ管理):")
    for scope, project_path, name, transport in sorted(project_actual):
        print(f"  [+{scope}]  {name} ({transport}) @ {project_path}")
    print()

sys.exit(1 if only_in_actual or only_in_files or mismatched or insecure_mode else 0)
PYEOF
