#!/usr/bin/env bash
# diff.sh
# servers.cache.json（システム実態）と servers.json（管理ファイル）の差分を表示する
#
# 動作:
#   [+cache] name  → システムに登録済みだが servers.json 未記載（IDE等が動的に追加した分を含む）
#   [-files] name  → servers.json にあるがシステム未登録（dots claude apply --mcp-only で追加できる）
#
# 使い方:
#   bash ai/claude/mcp/diff.sh           # 差分を詳細表示
#   bash ai/claude/mcp/diff.sh --summary # 1行サマリーのみ出力
#
# servers.cache.json が存在しない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="$DOTFILES_DIR/ai/claude/mcp/servers.json"
CACHE_FILE="$DOTFILES_DIR/ai/claude/mcp/servers.cache.json"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$CACHE_FILE" ]]; then
  exit 1
fi

python3 - "$SERVERS_FILE" "$CACHE_FILE" "$SUMMARY_MODE" << 'PYEOF'
import json
import sys

servers_path, cache_path, summary_mode = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(servers_path, encoding="utf-8") as f:
    declared = {entry["name"] for entry in json.load(f)}

with open(cache_path, encoding="utf-8") as f:
    actual = set(json.load(f).keys())

only_in_cache = sorted(actual - declared)
only_in_files = sorted(declared - actual)

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
    print("No diff: servers.cache.json と servers.json は一致しています。")
    sys.exit(0)

if only_in_cache:
    print("登録済みだが servers.json 未記載 (+cache のみ。IDE等による動的登録の可能性あり):")
    for name in only_in_cache:
        print(f"  [+cache]  {name}")
    print()
if only_in_files:
    print("servers.json にあるがシステム未登録 (-files のみ):")
    for name in only_in_files:
        print(f"  [-files]  {name}")

sys.exit(1)
PYEOF
