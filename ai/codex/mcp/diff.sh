#!/usr/bin/env bash
# Codex CLI が返す統合済みの MCP 実態と servers.json の差分を表示する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/codex/mcp/servers.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

actual_file="$(mktemp)"
trap 'rm -f "${actual_file}"' EXIT
codex mcp list --json > "${actual_file}"

python3 - "${SERVERS_FILE}" "${actual_file}" "${SUMMARY_MODE}" <<'PYEOF'
import json
import sys

servers_path, actual_path = sys.argv[1:3]
summary = sys.argv[3] == "1"

with open(servers_path, encoding="utf-8") as file:
    declared_entries = json.load(file)
with open(actual_path, encoding="utf-8") as file:
    actual_entries = json.load(file)

declared = {entry["name"]: entry for entry in declared_entries}
actual = {entry["name"]: entry for entry in actual_entries}
only_actual = sorted(actual.keys() - declared.keys())
only_files = sorted(declared.keys() - actual.keys())


def config_matches(wanted, current):
    transport = current.get("transport", {})
    if wanted["type"] == "stdio":
        return (
            transport.get("type") == "stdio"
            and transport.get("command") == wanted["command"]
            and transport.get("args", []) == wanted.get("args", [])
        )
    return (
        transport.get("type") in {"http", "streamable_http"}
        and transport.get("url") == wanted["url"]
        and not transport.get("bearer_token_env_var")
        and set(wanted.get("headers", {})).issubset(
            set(transport.get("http_headers") or {})
        )
    )


mismatched = sorted(
    name
    for name in declared.keys() & actual.keys()
    if not config_matches(declared[name], actual[name])
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
    print("No diff: 実際の MCP 登録状態と servers.json は一致しています。")
    raise SystemExit(0)

if only_actual:
    print("登録済みだが servers.json 未記載 (+actual のみ。アプリ・CLI・plugin 由来を含む):")
    for name in only_actual:
        transport = actual[name].get("transport", {}).get("type", "unknown")
        print(f"  [+actual]  {name} ({transport})")
    print()
if only_files:
    print("servers.json にあるが未登録 (-files のみ):")
    for name in only_files:
        print(f"  [-files]   {name}")
    print()
if mismatched:
    print("同名だが設定が不一致 (~config):")
    for name in mismatched:
        print(f"  [~config]  {name}")

raise SystemExit(1)
PYEOF
