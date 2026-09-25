#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   bash macos/sync_dockfile.sh          → dockfile を実機と完全一致させ、dockfile.cache を更新（dots dock sync）
#   bash macos/sync_dockfile.sh --merge  → 他マシン由来の項目を保持して更新（dots dock merge）
#   bash macos/sync_dockfile.sh --check  → 変更検知のみ（変更あれば exit 1）
#
# Options:
#   --dry-run  dockfile もキャッシュも書き換えず、変更予定（[add] / [remove]）だけを表示する
#   --yes      完全一致の sync で dockfile から項目が消える場合に必要（削除がなければ不要）。
#              他マシン由来の項目もここでは削除対象になる。残す場合は --merge を使う

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_FILE="${PRIVATE_DIR}/macos/dockfile"
SNAPSHOT="${PRIVATE_DIR}/macos/dockfile.cache"

MODE=""
MERGE=0
DRY_RUN=0
YES=0
while (( $# > 0 )); do
  case "$1" in
    --check) MODE="--check" ;;
    --merge) MERGE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) YES=1 ;;
    *) echo "usage: sync_dockfile.sh [--check|--merge] [--dry-run] [--yes]" >&2; exit 2 ;;
  esac
  shift
done

_mysides() {
  if command -v mysides &>/dev/null; then
    mysides "$@"
  elif command -v uv &>/dev/null; then
    uv run --with pyobjc python3 "$DOTFILES_DIR/macos/mysides.py" "$@"
  else
    echo "Error: sidebar tool unavailable — install uv: brew install uv" >&2
    return 1
  fi
}

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
  local output
  if output=$(_mysides list 2>/dev/null); then
    awk -F' -> ' '{print "sidebar\t" $1 "\t" $2}' <<< "$output"
  fi
}
_capture() {
  _current_dock | awk '{print "dock\t" $0}'
  _current_sidebar
}

# --check: 現在の Dock 状態と dockfile.cache を比較して差分検知のみ
if [[ "$MODE" == "--check" ]]; then
  if [[ ! -f "$SNAPSHOT" ]]; then
    echo "No dockfile.cache found. Run 'dots dock apply' to create one."
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

# dockfile を更新（常に実行）
dock_paths=$(_current_dock)
sidebar_ok=1
if ! sidebar_raw=$(_mysides list 2>/dev/null); then
  echo "Warning: sidebar tool not available. Existing sidebar entries in dockfile are kept as they are." >&2
  sidebar_raw=""
  sidebar_ok=0
fi

MERGE="$MERGE" DRY_RUN="$DRY_RUN" YES="$YES" SIDEBAR_OK="$sidebar_ok" \
python3 - "$DOCK_FILE" "$dock_paths" "$sidebar_raw" <<'PYEOF'
import os
import sys
from pathlib import Path
from urllib.parse import unquote
from collections import defaultdict

MERGE      = os.environ['MERGE'] == '1'
DRY_RUN    = os.environ['DRY_RUN'] == '1'
YES        = os.environ['YES'] == '1'
SIDEBAR_OK = os.environ['SIDEBAR_OK'] == '1'

dock_file      = Path(sys.argv[1])
current_paths  = [l for l in sys.argv[2].split('\n') if l.strip()]
sidebar_raw    = sys.argv[3]

def sidebar_url_to_path(url):
    p = unquote(url).removeprefix('file://').rstrip('/')
    return p if p else None

# ── 既存 dockfile を読み込み ───────────────────────────────────────────────────
old_dock_paths = []
old_sidebar    = []  # [(name, url), ...]
if dock_file.exists():
    for line in dock_file.read_text().splitlines():
        parts = line.split('\t')
        if parts[0] == 'dock' and len(parts) >= 2:
            old_dock_paths.append(parts[1])
        elif parts[0] == 'sidebar' and len(parts) >= 3:
            old_sidebar.append((parts[1], parts[2]))

# ── Dock アプリ: 順序を保持しながらマージ ─────────────────────────────────────
# 非ローカルエントリ（他マシン向け）を直前のローカルエントリ（アンカー）に紐付ける
current_set    = set(current_paths)
non_local_dock = {p for p in old_dock_paths if p not in current_set and not Path(p).exists()}

anchor_to_dock = defaultdict(list)  # anchor_path -> [non-local paths after it]
no_anchor_dock = []
last_anchor    = None
for p in old_dock_paths:
    if p in non_local_dock:
        if last_anchor is None:
            no_anchor_dock.append(p)
        else:
            anchor_to_dock[last_anchor].append(p)
    elif p in current_set:
        last_anchor = p

merged_dock = list(no_anchor_dock)
for p in current_paths:
    merged_dock.append(p)
    merged_dock.extend(anchor_to_dock.get(p, []))

# ── サイドバー: 順序を保持しながらマージ ──────────────────────────────────────
current_sidebar = {}  # name -> url
for line in sidebar_raw.splitlines():
    parts = line.split(' -> ', 1)
    if len(parts) == 2:
        current_sidebar[parts[0].strip()] = parts[1].strip()

current_names = set(current_sidebar.keys())
non_local_sb  = {name for name, url in old_sidebar
                 if name not in current_names
                 and not Path(sidebar_url_to_path(url) or '').exists()}

anchor_to_sb = defaultdict(list)  # anchor_name -> [(name, url)]
no_anchor_sb = []
last_sb_anchor = None
for name, url in old_sidebar:
    if name in non_local_sb:
        if last_sb_anchor is None:
            no_anchor_sb.append((name, url))
        else:
            anchor_to_sb[last_sb_anchor].append((name, url))
    elif name in current_names:
        last_sb_anchor = name

merged_sidebar = list(no_anchor_sb)
for name, url in current_sidebar.items():
    merged_sidebar.append((name, url))
    merged_sidebar.extend(anchor_to_sb.get(name, []))

# ── sync は実機と完全一致（他マシン由来の項目も残さない） ─────────────────────
# サイドバーを取得できなかった場合は、空で上書きしないよう既存のサイドバーを保つ
if not MERGE:
    merged_dock = list(current_paths)
    merged_sidebar = list(current_sidebar.items()) if SIDEBAR_OK else list(old_sidebar)
elif not SIDEBAR_OK:
    merged_sidebar = list(old_sidebar)

# ── 変更予定 ──────────────────────────────────────────────────────────────────
old_lines = [f'dock\t{p}' for p in old_dock_paths] + [f'sidebar\t{n}\t{u}' for n, u in old_sidebar]
lines = [f'dock\t{p}' for p in merged_dock]
lines += [f'sidebar\t{n}\t{u}' for n, u in merged_sidebar]
for line in lines:
    if line not in old_lines:
        print(f'[add]    {line}')
removed = [line for line in old_lines if line not in lines]
for line in removed:
    print(f'[remove] {line}')

if DRY_RUN:
    print('[dry-run] dockfile は変更していません')
    sys.exit(0)
if removed and not MERGE and not YES:
    print('error: dockfile から上記の項目を削除します（他マシン由来の項目を含む）。'
          '実行するには --yes を付けてください', file=sys.stderr)
    print('  （他マシン由来の項目を残す場合は dots dock merge）', file=sys.stderr)
    sys.exit(2)

# ── dockfile に書き出し ────────────────────────────────────────────────────────
dock_file.write_text('\n'.join(lines) + '\n')
PYEOF

[[ "$DRY_RUN" -eq 0 ]] || exit 0

# dockfile.cache を更新
export DOTFILES_DIR
bash "$DOTFILES_DIR/macos/update_dockcache.sh"
if [[ "$MERGE" -eq 1 ]]; then
  echo "dockfile merged."
else
  echo "dockfile synced."
fi
