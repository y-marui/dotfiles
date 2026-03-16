#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   bash macos/dock-sync.sh             → 変更検知・dock.sh 更新コマンド出力・snapshot 更新
#   bash macos/dock-sync.sh --check     → 変更検知のみ（変更あれば exit 1）
#   bash macos/dock-sync.sh --snapshot-only → snapshot だけ更新

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT="$DOTFILES_DIR/macos/dock-snapshot.txt"
MODE="${1:-}"

_current_dock() {
  dockutil --list 2>/dev/null | awk -F'\t' '{print "dock\t" $2}'
}
_current_sidebar() {
  mysides list 2>/dev/null | awk -F' -> ' '{print "sidebar\t" $1 "\t" $2}'
}
_capture() {
  _current_dock
  _current_sidebar
}

if [[ "$MODE" == "--snapshot-only" ]]; then
  _capture > "$SNAPSHOT"
  exit 0
fi

# 差分チェック
if [[ -f "$SNAPSHOT" ]]; then
  current=$(_capture)
  last=$(cat "$SNAPSHOT")
  if [[ "$current" == "$last" ]]; then
    echo "No changes detected."
    [[ "$MODE" == "--check" ]] && exit 0 || true
  else
    echo "Changes detected:"
    diff <(echo "$last") <(echo "$current") || true
    [[ "$MODE" == "--check" ]] && exit 1
  fi
else
  echo "No snapshot found. Run 'make dock' to create one."
  [[ "$MODE" == "--check" ]] && exit 1
fi

# dock.sh の該当セクション再生成コマンドを出力
echo ""
echo "=== dock.sh 用コマンド（該当セクションを置き換えてください） ==="
echo "# ── 標準アプリ（$(date '+%Y-%m-%d') sync）"
if command -v dockutil &>/dev/null; then
  dockutil --list 2>/dev/null | awk -F'\t' '{
    path = $2
    gsub("^file://", "", path)
    gsub(/%20/, " ", path)
    sub("/$", "", path)
    print "  dockutil --no-restart --add \"" path "\""
  }'
fi
echo ""
echo "# ── Finder サイドバー（$(date '+%Y-%m-%d') sync）"
if command -v mysides &>/dev/null; then
  mysides list 2>/dev/null | awk -F' -> ' '{print "  mysides add \"" $1 "\" \"" $2 "\""}'
fi

# snapshot を更新
_capture > "$SNAPSHOT"
echo ""
echo "Snapshot updated: $SNAPSHOT"
