#!/usr/bin/env bash
# Copilot CLI の user scope MCP と servers.json の差分を表示する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/copilot/mcp/servers.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

command -v copilot >/dev/null 2>&1 || exit 1

actual_file="$(mktemp)"
trap 'rm -f "${actual_file}"' EXIT
copilot mcp list --json > "${actual_file}"

python3 - "${SERVERS_FILE}" "${actual_file}" "${SUMMARY_MODE}" <<'PYEOF'
import json
import sys

servers_path, actual_path, summary_mode = sys.argv[1:]
summary = summary_mode == "1"

with open(servers_path, encoding="utf-8") as file:
    declared_entries = json.load(file)
with open(actual_path, encoding="utf-8") as file:
    all_actual = json.load(file).get("mcpServers", {})

declared = {entry["name"]: entry for entry in declared_entries}
actual = {
    name: entry
    for name, entry in all_actual.items()
    if entry.get("source") == "user"
}
other_sources = sorted(
    (name, entry.get("source", "unknown"))
    for name, entry in all_actual.items()
    if entry.get("source") != "user"
)


def matches(wanted, current):
    return (
        current.get("type") == wanted["type"]
        and current.get("command") == wanted.get("command")
        and current.get("args", []) == wanted.get("args", [])
        and current.get("tools", ["*"]) == wanted.get("tools", ["*"])
    )


only_actual = sorted(actual.keys() - declared.keys())
only_files = sorted(declared.keys() - actual.keys())
mismatched = sorted(
    name
    for name in declared.keys() & actual.keys()
    if not matches(declared[name], actual[name])
)

if summary:
    parts = []
    if only_actual:
        parts.append(f"+{len(only_actual)} actual のみ")
    if only_files:
        parts.append(f"-{len(only_files)} files のみ")
    if mismatched:
        parts.append(f"~{len(mismatched)} config 不一致")
    if parts:
        print(" / ".join(parts))
    raise SystemExit(1 if parts else 0)

if not only_actual and not only_files and not mismatched:
    print("No diff: Copilot CLI の user scope MCP と servers.json は一致しています。")
else:
    if only_actual:
        print("user scope に直接登録済みだが servers.json 未記載 (+actual のみ):")
        for name in only_actual:
            print(f"  [+actual]  {name}")
        print()
    if only_files:
        print("servers.json にあるが user scope 未登録 (-files のみ):")
        for name in only_files:
            print(f"  [-files]   {name}")
        print()
    if mismatched:
        print("同名だが設定が不一致 (~config):")
        for name in mismatched:
            print(f"  [~config]  {name}")
        print()

if other_sources:
    print("workspace / plugin / builtin MCP (Copilot CLI 管理):")
    for name, source in other_sources:
        print(f"  [{source}]  {name}")

raise SystemExit(1 if only_actual or only_files or mismatched else 0)
PYEOF
