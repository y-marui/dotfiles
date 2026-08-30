#!/usr/bin/env bash
# plugins.json と実際の Antigravity plugin ディレクトリを比較する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/gemini/plugin/plugins.json"
SOURCE_HOME="${DOTFILES_DIR}/ai/gemini/plugin/plugins"
PLUGIN_HOME="${HOME}/.gemini/config/plugins"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1
PYTHON_BIN="python3"

"${PYTHON_BIN}" - "${PLUGINS_FILE}" "${SOURCE_HOME}" "${PLUGIN_HOME}" "${SUMMARY_MODE}" <<'PYEOF'
import json
import os
import sys

plugins_file, source_home, plugin_home, summary = sys.argv[1:]
with open(plugins_file, encoding="utf-8") as file:
    declared = set(json.load(file).get("plugins", []))

actual = set()
if os.path.isdir(plugin_home):
    actual = {
        name
        for name in os.listdir(plugin_home)
        if os.path.isfile(os.path.join(plugin_home, name, "plugin.json"))
    }

source_missing = sorted(
    name for name in declared if not os.path.isfile(os.path.join(source_home, name, "plugin.json"))
)
mismatched = sorted(
    name
    for name in declared & actual
    if not os.path.islink(os.path.join(plugin_home, name))
    or os.readlink(os.path.join(plugin_home, name)) != os.path.join(source_home, name)
)
only_actual = sorted(actual - declared)
only_files = sorted(declared - actual)

parts = []
if only_actual:
    parts.append(f"+{len(only_actual)} actual のみ")
if only_files:
    parts.append(f"-{len(only_files)} files のみ")
if mismatched:
    parts.append(f"~{len(mismatched)} link 不一致")
if source_missing:
    parts.append(f"~{len(source_missing)} source 不足")
if summary == "1":
    if parts:
        print(" / ".join(parts))
    raise SystemExit(1 if parts else 0)

if not parts:
    print("No diff: Antigravity plugin の宣言と実体は一致しています。")
    raise SystemExit(0)
for label, names in (
    ("[+actual]", only_actual),
    ("[-files]", only_files),
    ("[~link]", mismatched),
    ("[~source]", source_missing),
):
    for name in names:
        print(f"  {label:<10} {name}")
raise SystemExit(1)
PYEOF
