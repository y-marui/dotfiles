#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   bash macos/sync_dockfile.sh          → dockfile 自動更新・dockfile.cache 更新
#   bash macos/sync_dockfile.sh --check  → 変更検知のみ（変更あれば exit 1）

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_FILE="${PRIVATE_DIR}/macos/dockfile"
SNAPSHOT="${PRIVATE_DIR}/macos/dockfile.cache"

MODE="${1:-}"

_current_dock() {
  dockutil --list 2>/dev/null | awk -F'\t' '{
    path = $2
    gsub("^file://", "", path)
    gsub(/%20/, " ", path)
    sub("/$", "", path)
    print path
  }'
}
_current_sidebar() {
  mysides list 2>/dev/null | awk -F' -> ' '{print "sidebar\t" $1 "\t" $2}'
}
_capture() {
  _current_dock | awk '{print "dock\t" $0}'
  _current_sidebar
}

# --check: 現在の Dock 状態と dockfile.cache を比較して差分検知のみ
if [[ "$MODE" == "--check" ]]; then
  if [[ ! -f "$SNAPSHOT" ]]; then
    echo "No dockfile.cache found. Run 'make dock' to create one."
    exit 1
  fi
  current=$(_capture)
  last=$(cat "$SNAPSHOT")
  if [[ "$current" == "$last" ]]; then
    echo "No changes detected."
    exit 0
  fi
  echo "Changes detected:"
  diff <(echo "$last") <(echo "$current") || true
  exit 1
fi

# dock ファイルをマージ更新（常に実行）
dock_paths=$(_current_dock)
sidebar_raw=$(mysides list 2>/dev/null)

python3 - "$DOCK_FILE" "$dock_paths" "$sidebar_raw" <<'PYEOF'
import sys
from pathlib import Path
from urllib.parse import unquote

dock_file      = Path(sys.argv[1])
current_paths  = [l for l in sys.argv[2].split('\n') if l.strip()]
sidebar_raw    = sys.argv[3]

def sidebar_url_to_path(url):
    p = unquote(url).removeprefix('file://').rstrip('/')
    return p if p else None

# ── 既存 dock ファイルを読み込み ───────────────────────────────────────────────
old_dock_paths = []
old_sidebar    = []  # [(name, url), ...]
if dock_file.exists():
    for line in dock_file.read_text().splitlines():
        parts = line.split('\t')
        if parts[0] == 'dock' and len(parts) >= 2:
            old_dock_paths.append(parts[1])
        elif parts[0] == 'sidebar' and len(parts) >= 3:
            old_sidebar.append((parts[1], parts[2]))

# ── Dock アプリ: マージ ────────────────────────────────────────────────────────
current_set = set(current_paths)
extra_dock  = [p for p in old_dock_paths if p not in current_set and not Path(p).exists()]
merged_dock = current_paths + extra_dock

# ── サイドバー: マージ ─────────────────────────────────────────────────────────
current_sidebar = {}  # name -> url
for line in sidebar_raw.splitlines():
    parts = line.split(' -> ', 1)
    if len(parts) == 2:
        current_sidebar[parts[0].strip()] = parts[1].strip()

current_names   = set(current_sidebar.keys())
extra_sidebar   = [
    (name, url) for name, url in old_sidebar
    if name not in current_names
    and not Path(sidebar_url_to_path(url) or '').exists()
]
merged_sidebar  = list(current_sidebar.items()) + extra_sidebar

# ── dock ファイルに書き出し ────────────────────────────────────────────────────
lines = [f'dock\t{p}' for p in merged_dock]
lines += [f'sidebar\t{n}\t{u}' for n, u in merged_sidebar]
dock_file.write_text('\n'.join(lines) + '\n')
PYEOF

# dockfile.cache を更新
export DOTFILES_DIR
bash "$DOTFILES_DIR/macos/update_dockcache.sh"
echo "dockfile synced."
