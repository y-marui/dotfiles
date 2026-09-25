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
# --add-only（dots npm merge）:
#   キャッシュにないパッケージを削除せず、追加とソートのみ行う（手順3を省く）
# --dry-run:
#   npmfile もキャッシュも書き換えず、変更予定（[add] / [remove]）だけを表示する
# --yes:
#   npmfile からの削除を伴う場合に必要（削除がなければ不要）。--add-only では不要
#
# 使い方:
#   bash npm/sync_npmfile.sh [--add-only] [--dry-run] [--yes]
#   dots npm sync
#   dots npm merge

set -euo pipefail

ADD_ONLY=0
DRY_RUN=0
YES=0
while (( $# > 0 )); do
  case "$1" in
    --add-only) ADD_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) YES=1 ;;
    *) echo "usage: sync_npmfile.sh [--add-only] [--dry-run] [--yes]" >&2; exit 2 ;;
  esac
  shift
done
MODE=synced
if [[ "$ADD_ONLY" -eq 1 ]]; then MODE=merged; fi

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NPMFILE="$DOTFILES_DIR/npm/npmfile"
NPMFILE_CACHE="$DOTFILES_DIR/npm/npmfile.cache"

# ── 現在の状態を取得（--dry-run ではキャッシュも書き換えない） ────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
  NPMFILE_CACHE="$(mktemp)"
  trap 'rm -f "$NPMFILE_CACHE"' EXIT
  bash "$DOTFILES_DIR/npm/update_npmcache.sh" --print > "$NPMFILE_CACHE"
else
  bash "$DOTFILES_DIR/npm/update_npmcache.sh"
fi

load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

to_add=$(comm -23 <(load_names "$NPMFILE_CACHE") <(load_names "$NPMFILE"))
to_remove=$(comm -13 <(load_names "$NPMFILE_CACHE") <(load_names "$NPMFILE"))
if [[ "$ADD_ONLY" -eq 1 ]]; then to_remove=""; fi

if [[ -n "$to_add"    ]]; then while IFS= read -r p; do echo "[add]    $p"; done <<< "$to_add"; fi
if [[ -n "$to_remove" ]]; then while IFS= read -r p; do echo "[remove] $p"; done <<< "$to_remove"; fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "[dry-run] npmfile は変更していません"
  exit 0
fi

if [[ -n "$to_remove" && "$YES" -eq 0 ]]; then
  echo "error: npmfile から上記のパッケージを削除します。実行するには --yes を付けてください" >&2
  echo "  （削除せず追加だけ行う場合は dots npm merge）" >&2
  exit 2
fi

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
echo "npmfile ${MODE}: +${added} added / -${removed} removed"
