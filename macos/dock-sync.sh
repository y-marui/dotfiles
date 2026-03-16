#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   bash macos/dock-sync.sh             → 変更検知・dock.sh 自動更新・dock.cache 更新
#   bash macos/dock-sync.sh --check     → 変更検知のみ（変更あれば exit 1）
#   bash macos/dock-sync.sh --snapshot-only → dock.cache だけ更新

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE_DIR="${DOTFILES_DIR}-private"
DOCK_SH="${PRIVATE_DIR}/macos/dock.sh"
SNAPSHOT="${PRIVATE_DIR}/macos/dock.cache"

if [[ ! -f "$DOCK_SH" ]]; then
  echo "Error: ${DOCK_SH} が見つかりません。make link を実行して dotfiles-private をセットアップしてください。" >&2
  exit 1
fi
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

if [[ "$MODE" == "--snapshot-only" ]]; then
  _capture > "$SNAPSHOT"
  exit 0
fi

# 差分チェック
if [[ -f "$SNAPSHOT" ]]; then
  current=$(_capture)
  last=$(cat "$SNAPSHOT")
  if [[ "$current" == "$last" ]]; then
    echo "No changes detected."
    [[ "$MODE" == "--check" ]] && exit 0 || exit 0
  fi
  echo "Changes detected:"
  diff <(echo "$last") <(echo "$current") || true
  [[ "$MODE" == "--check" ]] && exit 1
else
  echo "No snapshot found. Run 'make dock' to create one."
  [[ "$MODE" == "--check" ]] && exit 1
fi

# dock.sh をマージ更新
dock_paths=$(_current_dock)
sidebar_raw=$(mysides list 2>/dev/null)

python3 - "$DOCK_SH" "$dock_paths" "$sidebar_raw" <<'PYEOF'
import sys, re
from pathlib import Path
from urllib.parse import unquote

dock_sh        = Path(sys.argv[1])
current_paths  = [l for l in sys.argv[2].split('\n') if l.strip()]
sidebar_raw    = sys.argv[3]
content        = dock_sh.read_text()

def extract_path(line):
    m = re.search(r'(?:--add|_dock_add) "(.+?)"', line)
    return m.group(1) if m else None

def sidebar_url_to_path(url):
    # "file:///path/to/dir/" -> "/path/to/dir"
    p = unquote(url).removeprefix('file://').rstrip('/')
    return p if p else None

# ── Dock アプリ: マージ ────────────────────────────────────────────────────────
old_dock_match = re.search(
    r'# ── DOCK_APPS_BEGIN [─]+\n(.*?)  # ── DOCK_APPS_END',
    content, re.DOTALL)
old_dock_lines = old_dock_match.group(1).strip().splitlines() if old_dock_match else []
old_dock_paths = [p for l in old_dock_lines if (p := extract_path(l))]

current_set = set(current_paths)
extra_dock = [p for p in old_dock_paths if p not in current_set and not Path(p).exists()]
merged_dock = current_paths + extra_dock
new_dock = '\n'.join(f'  _dock_add "{p}"' for p in merged_dock)

# ── サイドバー: マージ ─────────────────────────────────────────────────────────
# current: mysides list の "name -> url" を解析
current_sidebar = {}  # name -> url
for line in sidebar_raw.splitlines():
    parts = line.split(' -> ', 1)
    if len(parts) == 2:
        current_sidebar[parts[0].strip()] = parts[1].strip()

# dock.sh の既存サイドバーエントリを抽出
old_sidebar_match = re.search(
    r'# ── SIDEBAR_BEGIN [─]+\n(.*?)  # ── SIDEBAR_END',
    content, re.DOTALL)
old_sidebar_lines = old_sidebar_match.group(1).strip().splitlines() if old_sidebar_match else []

def extract_sidebar_entry(line):
    m = re.search(r'_sidebar_add "(.+?)" "(.+?)"', line)
    return (m.group(1), m.group(2)) if m else None

old_sidebar = [e for l in old_sidebar_lines if (e := extract_sidebar_entry(l))]

# 現在のサイドバーにないが dock.sh にある → パスが存在しないものだけ保持
current_names = set(current_sidebar.keys())
extra_sidebar = [
    (name, url) for name, url in old_sidebar
    if name not in current_names
    and not Path(sidebar_url_to_path(url) or '').exists()
]

merged_sidebar_lines = (
    [f'  _sidebar_add "{n}" "{u}"' for n, u in current_sidebar.items()] +
    [f'  _sidebar_add "{n}" "{u}"' for n, u in extra_sidebar]
)
new_sidebar = '\n'.join(merged_sidebar_lines)

# ── 置換 ──────────────────────────────────────────────────────────────────────
def replace_section(text, tag, new_body):
    return re.sub(
        rf'(  # ── {tag}_BEGIN [─]+\n).*?(  # ── {tag}_END)',
        lambda m: m.group(1) + new_body + '\n' + m.group(2),
        text, flags=re.DOTALL)

content = replace_section(content, 'DOCK_APPS', new_dock)
content = replace_section(content, 'SIDEBAR',   new_sidebar)
dock_sh.write_text(content)
PYEOF

# snapshot を更新
_capture > "$SNAPSHOT"
echo "dock.sh updated. Snapshot saved to $SNAPSHOT"
