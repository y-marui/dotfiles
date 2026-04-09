#!/usr/bin/env bash
# diff_pipxfile.sh
# pipxfile.cache（システム実態）と pipxfile（管理ファイル）の差分を表示する
#
# 動作:
#   [+cache] package  → システムにインストール済みだが pipxfile 未記載
#   [-files] package  → pipxfile にあるがシステム未インストール
#
# 使い方:
#   bash pipx/diff_pipxfile.sh           # 差分を詳細表示
#   bash pipx/diff_pipxfile.sh --summary # 1行サマリーのみ出力（zlogin 用）
#
# pipxfile.cache が存在しない場合は終了コード 1 で何も出力しない

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PIPXFILE="$DOTFILES_DIR/pipx/pipxfile"
PIPXFILE_CACHE="$DOTFILES_DIR/pipx/pipxfile.cache"
SUMMARY_MODE=0
[[ "${1:-}" == "--summary" ]] && SUMMARY_MODE=1

if [[ ! -f "$PIPXFILE_CACHE" ]]; then
  exit 1
fi

# コメント・空行を除いてソート済みの一覧を作る
load_names() {
  grep -v '^\s*#' "$1" | grep -v '^\s*$' | sort
}

only_in_cache=$(comm -23 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))
only_in_files=$(comm -13 <(load_names "$PIPXFILE_CACHE") <(load_names "$PIPXFILE"))

if [[ $SUMMARY_MODE -eq 1 ]]; then
  parts=()
  [[ -n "$only_in_cache" ]] && parts+=("+$(echo "$only_in_cache" | wc -l | tr -d ' ') cache のみ")
  [[ -n "$only_in_files" ]] && parts+=("-$(echo "$only_in_files" | wc -l | tr -d ' ') files のみ")
  [[ ${#parts[@]} -gt 0 ]] && printf '%s\n' "$(IFS=' / '; echo "${parts[*]}")"
  exit 0
fi

if [[ -z "$only_in_cache" && -z "$only_in_files" ]]; then
  echo "No diff: pipxfile.cache と pipxfile は一致しています。"
  exit 0
fi

if [[ -n "$only_in_cache" ]]; then
  echo "インストール済みだが pipxfile 未記載 (+cache のみ):"
  while IFS= read -r pkg; do echo "  [+cache]  $pkg"; done <<< "$only_in_cache"
  echo
fi
if [[ -n "$only_in_files" ]]; then
  echo "pipxfile にあるがシステム未インストール (-files のみ):"
  while IFS= read -r pkg; do echo "  [-files]  $pkg"; done <<< "$only_in_files"
fi

exit 1
