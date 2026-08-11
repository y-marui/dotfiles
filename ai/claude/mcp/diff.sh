#!/usr/bin/env bash
# diff.sh
# ~/.claude.json の mcpServers（システム実態）と servers.json（管理ファイル）の差分を表示する
#
# ~/.claude.json を直接読むだけの軽量な処理（0.2秒程度）なので cache は持たない。
# claude CLI 経由か Claude.app（GUI）経由かを問わず、実際に登録されているものを検知できる。
#
# 動作:
#   [+actual] name  → システムに登録済みだが servers.json 未記載（IDE等が動的に追加した分を含む）
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
    actual = set(json.load(f).get("mcpServers", {}).keys())

only_in_actual = sorted(actual - declared)
only_in_files = sorted(declared - actual)

if summary_mode:
    parts = []
    if only_in_actual:
        parts.append(f"+{len(only_in_actual)} actual のみ")
    if only_in_files:
        parts.append(f"-{len(only_in_files)} files のみ")
    if parts:
        print(" / ".join(parts))
    sys.exit(0)

if not only_in_actual and not only_in_files:
    print("No diff: 実際の登録状態と servers.json は一致しています。")
    sys.exit(0)

if only_in_actual:
    print("登録済みだが servers.json 未記載 (+actual のみ。IDE・Claude.app等による動的登録の可能性あり):")
    for name in only_in_actual:
        print(f"  [+actual]  {name}")
    print()
if only_in_files:
    print("servers.json にあるがシステム未登録 (-files のみ):")
    for name in only_in_files:
        print(f"  [-files]  {name}")

sys.exit(1)
PYEOF
