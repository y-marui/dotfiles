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
#   dots pipx sync

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"

# ── pipxfile.cache を最新状態に更新 ───────────────────────────────────────────
bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"

load_names() {
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1" | sort
}

to_add=$(comm -23 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))
to_remove=$(comm -13 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))

if [[ -n "$to_add"    ]]; then while IFS= read -r p; do echo "[add]    $p"; done <<< "$to_add"; fi
if [[ -n "$to_remove" ]]; then while IFS= read -r p; do echo "[remove] $p"; done <<< "$to_remove"; fi

# ── pipxfile を書き戻す ───────────────────────────────────────────────────────
# コメント行・空行を保持しつつ、削除対象を除去、追加分を末尾に加えてソート。
# 既存の「仮想環境名 インストール元」行は、インストール元を失わずに保持する。
# コメント・空行は順序を保ち、パッケージ行だけをソートする。
grep -E '^\s*(#|$)' "$PIPXFILE" > "$PIPXFILE.tmp" || true
{
  while IFS= read -r entry; do
    [[ "$entry" =~ ^[[:space:]]*(#|$) ]] && continue
    name="${entry%%[[:space:]]*}"
    grep -Fqx "$name" <<< "$to_remove" || printf '%s\n' "$entry"
  done < "$PIPXFILE"

  [[ -n "$to_add" ]] && printf '%s\n' "$to_add"
} | sort -f >> "$PIPXFILE.tmp"

mv "$PIPXFILE.tmp" "$PIPXFILE"

added=$(echo "$to_add" | grep -c '.' || true)
removed=$(echo "$to_remove" | grep -c '.' || true)
echo ""
echo "pipxfile synced: +${added} added / -${removed} removed"
