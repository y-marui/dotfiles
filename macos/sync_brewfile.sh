#!/usr/bin/env bash
# sync_brewfile.sh
# Brewfile.local（実態）と Brewfile（dotfiles管理）を比較して Brewfile を更新する
#
# 動作:
#   1. Brewfile.local にしかないエントリ
#      1.1 Brewfile でコメントアウトされていれば解除
#      1.2 存在しなければ # ── 未分類 セクションに追加
#   2. Brewfile の重複エントリを除去（先に出現した行を残す）
#   3. 未分類セクションを type → name 順にソート
#
# ※ Brewfile にしかないエントリはコメントアウトしない（他 Mac の設定を保持）
#    他 Mac の変更を適用する場合は apply_brewfile.sh を使う
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
export BREWFILE="$DOTFILES_DIR/macos/Brewfile"
BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"

# ── Brewfile.local を最新状態に更新 ────────────────────────────────────────────
brew bundle dump --force --file="$BREWFILE_LOCAL"
# macOS の brew bundle dump は NFD で出力するため NFC に正規化する
python3 -c "
import unicodedata, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
with open(path, 'w', encoding='utf-8') as f:
    f.write(unicodedata.normalize('NFC', content))
" "$BREWFILE_LOCAL"

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

added=0; uncommented=0

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
    perl -i -0pe "s|^#[[:space:]]*(${type} \"${name}\"[^\n]*)|\$1|m" "$BREWFILE"
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

# ── 2. 重複除去 + 未分類ソート ──────────────────────────────────────────────────
python3 << 'PYEOF'
import re, os, sys

brewfile = os.environ.get('BREWFILE')
if not brewfile:
    sys.exit('BREWFILE not set')

with open(brewfile, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 重複除去: アクティブ・コメントアウト問わず先出現を残す
entry_pat = re.compile(r'^#?\s*(brew|cask|tap|mas|vscode) "([^"]+)"')
seen = set()
deduped = []
removed = 0
for line in lines:
    m = entry_pat.match(line)
    if m:
        key = f'{m.group(1)}|{m.group(2)}'
        if key in seen:
            removed += 1
            continue
        seen.add(key)
    deduped.append(line)

if removed:
    print(f'[dedup]     {removed} duplicate(s) removed')

# 未分類セクションをソート
TYPE_ORDER = {'brew': 0, 'cask': 1, 'tap': 2, 'mas': 3, 'vscode': 4}
section_pat = re.compile(r'^# ── 未分類')

result = []
i = 0
while i < len(deduped):
    if section_pat.match(deduped[i]):
        result.append(deduped[i])  # セクションヘッダ
        i += 1
        section_lines = []
        while i < len(deduped) and not re.match(r'^# ──', deduped[i]):
            section_lines.append(deduped[i])
            i += 1
        # エントリ行とそれ以外（空行等）に分ける
        entry_lines = [l for l in section_lines if entry_pat.match(l)]
        other_lines = [l for l in section_lines if not entry_pat.match(l)]
        def sort_key(line):
            m = entry_pat.match(line)
            return (TYPE_ORDER.get(m.group(1), 9), m.group(2).lower())
        entry_lines.sort(key=sort_key)
        result.extend(entry_lines)
        result.extend(l for l in other_lines if l.strip())  # 空行は末尾に1つだけ
        if result and result[-1] != '\n':
            result.append('\n')
    else:
        result.append(deduped[i])
        i += 1

with open(brewfile, 'w', encoding='utf-8') as f:
    f.writelines(result)
PYEOF

# ── 結果サマリー ────────────────────────────────────────────────────────────────
echo ""
echo "Brewfile synced: +${added} added / ${uncommented} uncommented"
