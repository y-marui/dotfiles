#!/usr/bin/env bash
# sync_brewfile.sh
# Brewfile.local（実態）と Brewfile（dotfiles管理）を比較して Brewfile を更新する
#
# 動作:
#   1. Brewfile.local にしかないエントリ
#      1.1 Brewfile でコメントアウトされていれば解除
#      1.2 存在しなければ # ── 未分類 セクションに追加
#   2. Brewfile にしかないエントリ → コメントアウト
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash sync_brewfile.sh
#
# brew のラッパー関数から自動呼び出しする場合は .zshrc に以下を追加:
#   brew() {
#     command brew "$@"
#     case "$1" in
#       install|uninstall|tap|untap|upgrade)
#         bash "$DOTFILES_DIR/macos/sync_brewfile.sh"
#         ;;
#     esac
#   }

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE="$DOTFILES_DIR/macos/Brewfile"
BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"

# ── Brewfile.local を最新状態に更新 ────────────────────────────────────────────
brew bundle dump --force --file="$BREWFILE_LOCAL"

# ── ヘルパー関数 ────────────────────────────────────────────────────────────────

# コメント行・空行を除いたエントリを抽出してソート
extract_entries() {
  grep -E '^(brew|cask|tap|mas|vscode) ' "$1" | sort
}

# "brew "git"" → "brew|git" に正規化（比較用）
normalize() {
  sed -E 's/^(brew|cask|tap|mas|vscode) "([^"]+)".*/\1|\2/'
}

# ── エントリ収集 ────────────────────────────────────────────────────────────────
local_entries=$(extract_entries "$BREWFILE_LOCAL" | normalize)
brewfile_entries=$(grep -E '^(brew|cask|tap|mas|vscode) ' "$BREWFILE" | normalize)
commented_entries=$(grep -E '^#\s*(brew|cask|tap|mas|vscode) ' "$BREWFILE" \
  | sed 's/^#[[:space:]]*//' | normalize)

added=0; commented_out=0; uncommented=0

# ── 1. Brewfile.local にしかないエントリを処理 ──────────────────────────────────
while IFS='|' read -r type name; do
  [[ -z "$type" || -z "$name" ]] && continue
  key="$type|$name"

  # すでに Brewfile にアクティブなエントリとして存在する場合はスキップ
  if echo "$brewfile_entries" | grep -qF "$key"; then
    continue
  fi

  # 1.1 コメントアウトされていれば解除
  if echo "$commented_entries" | grep -qF "$key"; then
    perl -i -0pe "s/^#[[:space:]]*($type \"$name\"[^\n]*)/\$1/m" "$BREWFILE"
    echo "[uncomment] $type \"$name\""
    uncommented=$((uncommented + 1))
    continue
  fi

  # 1.2 未分類セクションがなければ末尾に作成
  if ! grep -q '^# ── 未分類' "$BREWFILE"; then
    printf '\n# ── 未分類 ────────────────────────────────────────────────────────────────────\n' >> "$BREWFILE"
  fi

  # 重複チェックしてから追加
  if ! grep -qF "$type \"$name\"" "$BREWFILE"; then
    echo "$type \"$name\"" >> "$BREWFILE"
    echo "[add]       $type \"$name\""
    added=$((added + 1))
  fi

done << EOF
$local_entries
EOF

# ── 2. Brewfile にしかないエントリをコメントアウト ──────────────────────────────
while IFS='|' read -r type name; do
  [[ -z "$type" || -z "$name" ]] && continue
  key="$type|$name"

  if ! echo "$local_entries" | grep -qF "$key"; then
    perl -i -0pe "s/^($type \"$name\"[^\n]*)/#\$1/m" "$BREWFILE"
    echo "[comment]   $type \"$name\""
    commented_out=$((commented_out + 1))
  fi

done << EOF
$brewfile_entries
EOF

# ── 結果サマリー ────────────────────────────────────────────────────────────────
echo ""
echo "Brewfile synced: +${added} added / ${uncommented} uncommented / ${commented_out} commented out"
