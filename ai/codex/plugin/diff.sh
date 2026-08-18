#!/usr/bin/env bash
# Codex CLI が返す plugin 実態と plugins.json の差分を表示する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/codex/plugin/plugins.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

actual_file="$(mktemp)"
trap 'rm -f "${actual_file}"' EXIT
codex plugin list --json > "${actual_file}"

python3 - "${PLUGINS_FILE}" "${actual_file}" "${SUMMARY_MODE}" <<'PYEOF'
import json
import sys

plugins_path, actual_path = sys.argv[1:3]
summary = sys.argv[3] == "1"

with open(plugins_path, encoding="utf-8") as file:
    declared = set(json.load(file).get("plugins", []))
with open(actual_path, encoding="utf-8") as file:
    actual = {
        entry["pluginId"]
        for entry in json.load(file).get("installed", [])
        if entry.get("installed", True)
    }

only_actual = sorted(actual - declared)
only_files = sorted(declared - actual)

if summary:
    parts = []
    if only_actual:
        parts.append(f"+{len(only_actual)} actual のみ")
    if only_files:
        parts.append(f"-{len(only_files)} files のみ")
    if parts:
        print(" / ".join(parts))
    raise SystemExit(1 if parts else 0)

if not only_actual and not only_files:
    print("No diff: 実際の plugin インストール状態と plugins.json は一致しています。")
    raise SystemExit(0)

if only_actual:
    print("インストール済みだが plugins.json 未記載 (+actual のみ。local/remote source を含む):")
    for name in only_actual:
        print(f"  [+actual]  {name}")
    print()
if only_files:
    print("plugins.json にあるが未インストール (-files のみ):")
    for name in only_files:
        print(f"  [-files]   {name}")

raise SystemExit(1)
PYEOF
