#!/usr/bin/env bash
# Codex CLI が返す統合済みの MCP 実態と servers.json の差分を表示する。

set -euo pipefail
umask 077

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/codex/mcp/servers.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

actual_file="$(mktemp)"
plugins_file="$(mktemp)"
trap 'rm -f "${actual_file}" "${plugins_file}"' EXIT
codex mcp list --json > "${actual_file}"
codex plugin list --json > "${plugins_file}"

python3 - "${SERVERS_FILE}" "${actual_file}" "${plugins_file}" "${SUMMARY_MODE}" <<'PYEOF'
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

servers_path, actual_path, plugins_path = sys.argv[1:4]
summary = sys.argv[4] == "1"

with open(servers_path, encoding="utf-8") as file:
    declared_entries = json.load(file)
with open(actual_path, encoding="utf-8") as file:
    actual_entries = json.load(file)
with open(plugins_path, encoding="utf-8") as file:
    plugin_entries = json.load(file).get("installed", [])

declared = {entry["name"]: entry for entry in declared_entries}
actual = {entry["name"]: entry for entry in actual_entries}
plugin_owned = {}
for plugin in plugin_entries:
    if not plugin.get("installed", True):
        continue
    source_path = plugin.get("source", {}).get("path")
    if not source_path:
        continue
    manifest_path = Path(source_path) / ".mcp.json"
    try:
        with manifest_path.open(encoding="utf-8") as file:
            manifest = json.load(file)
    except (FileNotFoundError, PermissionError, json.JSONDecodeError):
        continue
    for name in manifest.get("mcpServers", {}):
        plugin_owned[name] = plugin["pluginId"]


def is_app_owned(entry):
    command = entry.get("transport", {}).get("command", "")
    return command.startswith("/Applications/ChatGPT.app/")


def is_loopback(entry):
    hostname = urlparse(entry.get("transport", {}).get("url", "")).hostname
    return hostname in {"127.0.0.1", "localhost", "::1"}


extra_names = actual.keys() - declared.keys()
plugin_actual = sorted(name for name in extra_names if name in plugin_owned)
app_actual = sorted(
    name for name in extra_names if name not in plugin_owned and is_app_owned(actual[name])
)
loopback_actual = sorted(
    name
    for name in extra_names
    if name not in plugin_owned and name not in app_actual and is_loopback(actual[name])
)
only_actual = sorted(
    set(extra_names) - set(plugin_actual) - set(app_actual) - set(loopback_actual)
)
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
else:
    if only_actual:
        print("直接登録済みだが servers.json 未記載 (+actual のみ):")
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
        print()

if plugin_actual:
    print("plugin が提供する MCP (plugin 管理):")
    for name in plugin_actual:
        print(f"  [plugin]   {name} <- {plugin_owned[name]}")
    print()
if app_actual:
    print("ChatGPT/Codex アプリが提供する内部 MCP (app 管理):")
    for name in app_actual:
        print(f"  [app]      {name}")
    print()
if loopback_actual:
    print("IDE/app が提供する loopback MCP (app 管理):")
    for name in loopback_actual:
        print(f"  [app]      {name}")

raise SystemExit(1 if only_actual or only_files or mismatched else 0)
PYEOF
