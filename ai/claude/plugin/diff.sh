#!/usr/bin/env bash
# diff.sh
# plugins.cache.json（システム実態）と plugins.json（管理ファイル）の差分を表示する
#
# 使い方:
#   bash ai/claude/plugin/diff.sh           # 差分を詳細表示
#   bash ai/claude/plugin/diff.sh --summary # 1行サマリーのみ出力
#
# plugins.cache.json が存在しない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="$DOTFILES_DIR/ai/claude/plugin/plugins.json"
CACHE_FILE="$DOTFILES_DIR/ai/claude/plugin/plugins.cache.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$CACHE_FILE" ]]; then
  exit 1
fi

python3 - "$PLUGINS_FILE" "$CACHE_FILE" "$SUMMARY_MODE" << 'PYEOF'
import json
import sys

declared_path, cache_path, summary_mode = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(declared_path, encoding="utf-8") as f:
    declared = json.load(f)
with open(cache_path, encoding="utf-8") as f:
    actual = json.load(f)

declared_mkt = {m["name"] for m in declared.get("marketplaces", [])}
actual_mkt = {m["name"] for m in actual.get("marketplaces", [])}
declared_plugins = set(declared.get("plugins", []))
actual_plugins = set(actual.get("plugins", []))

only_in_cache = sorted((actual_mkt - declared_mkt)) + sorted((actual_plugins - declared_plugins))
only_in_files = sorted((declared_mkt - actual_mkt)) + sorted((declared_plugins - actual_plugins))

if summary_mode:
    parts = []
    if only_in_cache:
        parts.append(f"+{len(only_in_cache)} cache のみ")
    if only_in_files:
        parts.append(f"-{len(only_in_files)} files のみ")
    if parts:
        print(" / ".join(parts))
    sys.exit(0)

if not only_in_cache and not only_in_files:
    print("No diff: plugins.cache.json と plugins.json は一致しています。")
    sys.exit(0)

if only_in_cache:
    print("インストール済みだが plugins.json 未記載 (+cache のみ):")
    for name in only_in_cache:
        print(f"  [+cache]  {name}")
    print()
if only_in_files:
    print("plugins.json にあるが未インストール (-files のみ):")
    for name in only_in_files:
        print(f"  [-files]  {name}")

sys.exit(1)
PYEOF
