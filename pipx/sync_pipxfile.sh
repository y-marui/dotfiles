#!/usr/bin/env bash
# sync_pipxfile.sh
# 現在の pipx パッケージ状態を pipxfile に同期する
#
# 動作:
#   1. pipxfile.cache を最新化
#   2. pipxfile にないパッケージをキャッシュから追加
#   3. キャッシュにないパッケージを pipxfile から削除
#   4. パッケージ行をアルファベット順にソート
#
# 使い方:
#   bash pipx/sync_pipxfile.sh
#   make pipx-sync

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"

# ── pipxfile.cache を最新状態に更新 ───────────────────────────────────────────
bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

to_add=$(comm -23 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))
to_remove=$(comm -13 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))

if [[ -n "$to_add"    ]]; then while IFS= read -r p; do echo "[add]    $p"; done <<< "$to_add"; fi
if [[ -n "$to_remove" ]]; then while IFS= read -r p; do echo "[remove] $p"; done <<< "$to_remove"; fi

# ── pipxfile を書き戻す ───────────────────────────────────────────────────────
# コメント行・空行を保持しつつ、削除対象を除去、追加分を末尾に加えてソート
{
  # コメント・空行はそのまま残す
  grep -E '^\s*(#|$)' "$PIPXFILE" || true

  # パッケージ行：削除対象を除いたうえで追加分とまとめてソート
  {
    grep -v '^\s*#' "$PIPXFILE" | grep -v '^\s*$' || true
    echo "$to_add"
  } | grep -v '^\s*$' \
    | grep -vFf <(echo "$to_remove" | grep -v '^\s*$' || true) \
    | sort -f
} > "$PIPXFILE.tmp"

mv "$PIPXFILE.tmp" "$PIPXFILE"

added=$(echo "$to_add" | grep -c '.' || true)
removed=$(echo "$to_remove" | grep -c '.' || true)
echo ""
echo "pipxfile synced: +${added} added / -${removed} removed"
