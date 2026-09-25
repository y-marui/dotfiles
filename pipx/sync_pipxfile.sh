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
# --add-only（dots pipx merge）:
#   キャッシュにないパッケージを削除せず、追加とソートのみ行う（手順3を省く）
# --dry-run:
#   pipxfile もキャッシュも書き換えず、変更予定（[add] / [remove]）だけを表示する
# --yes:
#   pipxfile からの削除を伴う場合に必要（削除がなければ不要）。--add-only では不要
#
# 使い方:
#   bash pipx/sync_pipxfile.sh [--add-only] [--dry-run] [--yes]
#   dots pipx sync
#   dots pipx merge

set -euo pipefail

ADD_ONLY=0
DRY_RUN=0
YES=0
while (( $# > 0 )); do
  case "$1" in
    --add-only) ADD_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) YES=1 ;;
    *) echo "usage: sync_pipxfile.sh [--add-only] [--dry-run] [--yes]" >&2; exit 2 ;;
  esac
  shift
done
MODE=synced
if [[ "$ADD_ONLY" -eq 1 ]]; then MODE=merged; fi

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"

# ── 現在の状態を取得（--dry-run ではキャッシュも書き換えない） ────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
  PIPXFILE_CACHE="$(mktemp)"
  trap 'rm -f "$PIPXFILE_CACHE"' EXIT
  bash "$DOTFILES_DIR/pipx/update_pipxcache.sh" --print > "$PIPXFILE_CACHE"
else
  bash "$DOTFILES_DIR/pipx/update_pipxcache.sh"
fi

load_names() {
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1" | sort
}

to_add=$(comm -23 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))
to_remove=$(comm -13 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))
if [[ "$ADD_ONLY" -eq 1 ]]; then to_remove=""; fi

if [[ -n "$to_add"    ]]; then while IFS= read -r p; do echo "[add]    $p"; done <<< "$to_add"; fi
if [[ -n "$to_remove" ]]; then while IFS= read -r p; do echo "[remove] $p"; done <<< "$to_remove"; fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "[dry-run] pipxfile は変更していません"
  exit 0
fi

if [[ -n "$to_remove" && "$YES" -eq 0 ]]; then
  echo "error: pipxfile から上記のパッケージを削除します。実行するには --yes を付けてください" >&2
  echo "  （削除せず追加だけ行う場合は dots pipx merge）" >&2
  exit 2
fi

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

  if [[ -n "$to_add" ]]; then printf '%s\n' "$to_add"; fi
} | sort -f >> "$PIPXFILE.tmp"

mv "$PIPXFILE.tmp" "$PIPXFILE"

added=$(echo "$to_add" | grep -c '.' || true)
removed=$(echo "$to_remove" | grep -c '.' || true)
echo ""
echo "pipxfile ${MODE}: +${added} added / -${removed} removed"
