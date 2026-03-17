#!/usr/bin/env bash
# sync_npmfile.sh
# 現在の npm グローバルパッケージ状態を npmfile に同期する
#
# 動作:
#   1. npmfile.cache を最新化
#   2. npmfile にないパッケージをキャッシュから追加
#   3. キャッシュにないパッケージを npmfile から削除
#   4. パッケージ行をアルファベット順にソート
#
# 使い方:
#   bash npm/sync_npmfile.sh
#   make npm-sync

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE="$DOTFILES_DIR/npm/npmfile"
NPMFILE_CACHE="$DOTFILES_DIR/npm/npmfile.cache"

# ── npmfile.cache を最新状態に更新 ────────────────────────────────────────────
bash "$DOTFILES_DIR/npm/update_npmcache.sh"

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

to_add=$(comm -23 <(load_names "$NPMFILE_CACHE") <(load_names "$NPMFILE"))
to_remove=$(comm -13 <(load_names "$NPMFILE_CACHE") <(load_names "$NPMFILE"))

if [[ -n "$to_add"    ]]; then while IFS= read -r p; do echo "[add]    $p"; done <<< "$to_add"; fi
if [[ -n "$to_remove" ]]; then while IFS= read -r p; do echo "[remove] $p"; done <<< "$to_remove"; fi

# ── npmfile を書き戻す ────────────────────────────────────────────────────────
# コメント行・空行を保持しつつ、削除対象を除去、追加分を末尾に加えてソート
{
  # コメント・空行はそのまま残す
  grep -E '^\s*(#|$)' "$NPMFILE" || true

  # パッケージ行：削除対象を除いたうえで追加分とまとめてソート
  {
    grep -v '^\s*#' "$NPMFILE" | grep -v '^\s*$' || true
    echo "$to_add"
  } | grep -v '^\s*$' \
    | grep -vFf <(echo "$to_remove" | grep -v '^\s*$' || true) \
    | sort -f
} > "$NPMFILE.tmp"

mv "$NPMFILE.tmp" "$NPMFILE"

added=$(echo "$to_add" | grep -c '.' || true)
removed=$(echo "$to_remove" | grep -c '.' || true)
echo ""
echo "npmfile synced: +${added} added / -${removed} removed"
