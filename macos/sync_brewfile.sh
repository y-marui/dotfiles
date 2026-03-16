#!/usr/bin/env bash
# sync_brewfile.sh
# Brewfile.dump（システム実態）と Brewfile（dotfiles管理）を完全一致させ、
# Brewfile.local（マシン固有パッケージ）も整合させる
#
# 動作:
#   1. brew bundle dump で Brewfile.dump を最新化（システム実態）
#   2. Brewfile.dump にないエントリを Brewfile から削除
#   3. Brewfile.dump にあって Brewfile にないエントリを 未分類 セクションに追加
#   4. 全セクションのエントリをアルファベット順にソート
#   5. 重複除去
#   6. Brewfile.local を整合：
#      - システムから削除されたエントリを除去（Brewfile.dump にない）
#      - Brewfile に昇格したエントリを除去（重複防止）
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
export BREWFILE_CACHE="$DOTFILES_DIR/macos/Brewfile.cache"
export BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"

# ── Brewfile.cache を最新状態に更新 ────────────────────────────────────────────
bash "$DOTFILES_DIR/macos/update_brewcache.sh"

# ── Brewfile を Brewfile.cache と同期 ──────────────────────────────────────────
python3 << 'PYEOF'
import re, os, sys

BREWFILE       = os.environ['BREWFILE']
BREWFILE_CACHE = os.environ['BREWFILE_CACHE']

ENTRY_PAT    = re.compile(r'^(brew|cask|tap|mas|vscode) "([^"]+)"')
SECTION_PAT  = re.compile(r'^# ──')
TYPE_ORDER   = {'brew': 0, 'cask': 1, 'tap': 2, 'mas': 3, 'vscode': 4}
UNCLASSIFIED = '# ── 未分類 ────────────────────────────────────────────────────────────────────'

def sort_key(line):
    m = ENTRY_PAT.match(line)
    return (TYPE_ORDER.get(m.group(1), 9), m.group(2).lower())

# ── Brewfile.cache のエントリを収集 ──────────────────────────────────────────
dump_entries = {}  # key -> full line
with open(BREWFILE_CACHE, encoding='utf-8') as f:
    for line in f:
        m = ENTRY_PAT.match(line)
        if m:
            dump_entries[f'{m.group(1)}|{m.group(2)}'] = line

# ── Brewfile を走査：既存エントリのうち cache にあるものだけ残す ─────────────
with open(BREWFILE, encoding='utf-8') as f:
    lines = f.readlines()

# セクション構造を維持しながら処理
Section = list  # [(header_line, [entry_lines])]

sections = []          # (header, entries)
current_header = None
current_entries = []
pre_header_lines = []  # セクション前のコメント・空行

seen_keys = set()
added = removed = 0

def flush_section():
    if current_header is not None:
        sections.append((current_header, list(current_entries)))

i = 0
while i < len(lines):
    line = lines[i]
    if SECTION_PAT.match(line):
        flush_section()
        current_header = line
        current_entries = []
    elif ENTRY_PAT.match(line):
        m = ENTRY_PAT.match(line)
        key = f'{m.group(1)}|{m.group(2)}'
        if key in seen_keys:
            # 重複: 削除
            pass
        elif key in dump_entries:
            seen_keys.add(key)
            # Brewfile.dump の行（id つき等）で上書き
            current_entries.append(dump_entries[key])
        else:
            removed += 1
            print(f'[remove]    {line.rstrip()}')
    else:
        if current_header is None:
            pre_header_lines.append(line)
        else:
            current_entries.append(line)
    i += 1

flush_section()

# ── Brewfile.local のキーを収集（存在する場合）────────────────────────────────
# Brewfile.local のパッケージは Brewfile に自動昇格させない
local_keys = set()
try:
    with open(os.environ['BREWFILE_LOCAL'], encoding='utf-8') as f:
        for line in f:
            m = ENTRY_PAT.match(line)
            if m:
                local_keys.add(f'{m.group(1)}|{m.group(2)}')
except FileNotFoundError:
    pass

# ── Brewfile にないエントリを 未分類 セクションへ追加 ─────────────────────────
# ただし Brewfile.local にあるものは除外（そちらで管理するため）
new_entries = [line for key, line in dump_entries.items()
               if key not in seen_keys and key not in local_keys]
if new_entries:
    # 未分類セクションを探す
    unc_idx = next((i for i, (h, _) in enumerate(sections)
                    if '未分類' in h), None)
    if unc_idx is None:
        sections.append((UNCLASSIFIED + '\n', []))
        unc_idx = len(sections) - 1
    for line in new_entries:
        sections[unc_idx][1].append(line)
        added += 1
        print(f'[add]       {line.rstrip()}')

# ── 各セクション内をソート ────────────────────────────────────────────────────
def sort_section(entries):
    entry_lines = [l for l in entries if ENTRY_PAT.match(l)]
    other_lines = [l for l in entries if not ENTRY_PAT.match(l) and l.strip()]
    entry_lines.sort(key=sort_key)
    result = entry_lines + other_lines
    if result:
        result.append('\n')
    return result

# ── 書き戻し ─────────────────────────────────────────────────────────────────
output = pre_header_lines
for header, entries in sections:
    output.append(header)
    output.extend(sort_section(entries))

# 末尾の余分な空行をすべて除去
while output and output[-1] == '\n':
    output.pop()

with open(BREWFILE, 'w', encoding='utf-8') as f:
    f.writelines(output)

print(f'\nBrewfile synced: +{added} added / -{removed} removed')
PYEOF

# ── Brewfile.local を整合（存在する場合のみ） ─────────────────────────────────
if [[ -f "$BREWFILE_LOCAL" ]]; then
  python3 << 'PYEOF'
import re, os

BREWFILE        = os.environ['BREWFILE']
BREWFILE_CACHE  = os.environ['BREWFILE_CACHE']
BREWFILE_LOCAL  = os.environ['BREWFILE_LOCAL']

ENTRY_PAT = re.compile(r'^(brew|cask|tap|mas|vscode) "([^"]+)"')

def load_keys(path):
    keys = set()
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                m = ENTRY_PAT.match(line)
                if m:
                    keys.add(f'{m.group(1)}|{m.group(2)}')
    except FileNotFoundError:
        pass
    return keys

dump_keys = load_keys(BREWFILE_CACHE)
main_keys = load_keys(BREWFILE)

with open(BREWFILE_LOCAL, encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
removed = 0
for line in lines:
    m = ENTRY_PAT.match(line)
    if not m:
        new_lines.append(line)
        continue
    key = f'{m.group(1)}|{m.group(2)}'
    if key not in dump_keys:
        print(f'[local remove] {line.rstrip()} (システムから削除済)')
        removed += 1
    elif key in main_keys:
        print(f'[local remove] {line.rstrip()} (Brewfile に昇格済)')
        removed += 1
    else:
        new_lines.append(line)

# 末尾の余分な空行をすべて除去
while new_lines and new_lines[-1] == '\n':
    new_lines.pop()

with open(BREWFILE_LOCAL, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f'Brewfile.local synced: -{removed} removed')
PYEOF
fi
