#!/usr/bin/env bash
# apply_brewfile.sh
# Brewfile / Brewfile.local の内容をローカルの Homebrew 環境に適用する
#
# 動作:
#   オプションなし（dots brew apply --full）:
#     1. Brewfile / Brewfile.local を全件適用
#     2. ローカルにあって管理ファイルにないものをcleanup
#   --diff-only（dots brew apply）:
#     1. Brewfile.cacheとの差分から不足エントリだけを適用
#     2. 余分なエントリがある場合だけcleanup
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash apply_brewfile.sh [--diff-only] [--force]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE="$DOTFILES_DIR/macos/Brewfile"
BREWFILE_CACHE="$DOTFILES_DIR/macos/Brewfile.cache"
BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"
FORCE=0
DIFF_ONLY=0
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --diff-only) DIFF_ONLY=1 ;;
    *) echo "error: unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Brewfile と Brewfile.local を合わせて cleanup（local のパッケージを誤削除しない）
COMBINED=$(mktemp)
DELTA=$(mktemp)
trap 'rm -f "$COMBINED" "$DELTA"' EXIT
cat "$BREWFILE" > "$COMBINED"
if [[ -f "$BREWFILE_LOCAL" ]]; then
  cat "$BREWFILE_LOCAL" >> "$COMBINED"
fi

missing_count=0
extra_count=0

if [[ $DIFF_ONLY -eq 1 ]]; then
  if [[ ! -f "$BREWFILE_CACHE" ]]; then
    echo "error: Brewfile.cache not found: $BREWFILE_CACHE" >&2
    exit 1
  fi

  read -r missing_count extra_count < <(
    python3 - "$BREWFILE_CACHE" "$BREWFILE" "$BREWFILE_LOCAL" "$DELTA" <<'PYEOF'
import re
import sys
from pathlib import Path

cache_path, brewfile_path, local_path, delta_path = map(Path, sys.argv[1:])
entry_pattern = re.compile(r'^(brew|cask|tap|mas|vscode) "([^"]+)"')


def load_keys(path):
    keys = set()
    if not path.exists():
        return keys
    for line in path.read_text(encoding="utf-8").splitlines():
        match = entry_pattern.match(line)
        if match:
            keys.add((match.group(1), match.group(2)))
    return keys


cache_keys = load_keys(cache_path)
managed_keys = set()
missing_lines = []

for path in (brewfile_path, local_path):
    if not path.exists():
        continue
    for line in path.read_text(encoding="utf-8").splitlines():
        match = entry_pattern.match(line)
        if not match:
            continue
        key = (match.group(1), match.group(2))
        if key in managed_keys:
            continue
        managed_keys.add(key)
        if key not in cache_keys:
            missing_lines.append(line)

delta_path.write_text(
    "\n".join(missing_lines) + ("\n" if missing_lines else ""),
    encoding="utf-8",
)
print(len(missing_lines), len(cache_keys - managed_keys))
PYEOF
  )

  if [[ $missing_count -gt 0 ]]; then
    echo "==> Installing ${missing_count} missing Brewfile entries..."
    brew bundle install --file="$DELTA"
  else
    echo "==> No missing Brewfile entries."
  fi
else
  # 現在のdots brew apply --fullと同じ全件適用。
  echo "==> Installing packages from Brewfile..."
  brew bundle install --file="$BREWFILE"

  if [[ -f "$BREWFILE_LOCAL" ]]; then
    echo ""
    echo "==> Installing packages from Brewfile.local..."
    brew bundle install --file="$BREWFILE_LOCAL"
  fi
fi

# ── 不要パッケージの削除 ─────────────────────────────────────────────────────
if [[ $DIFF_ONLY -eq 0 || $extra_count -gt 0 ]]; then
  echo ""
  echo "==> Checking for packages not in Brewfile or Brewfile.local..."
  if [[ $FORCE -eq 1 ]]; then
    brew bundle cleanup --force --file="$COMBINED"
  else
    brew bundle cleanup --file="$COMBINED"
  fi
else
  echo "==> No unmanaged Brewfile entries."
fi

# ── mas アンインストール対象の警告 ────────────────────────────────────────────
# brew bundle cleanup は mas を対象外にするため、手動対応が必要なものを表示する
if command -v mas &>/dev/null && [[ $DIFF_ONLY -eq 0 || $extra_count -gt 0 ]]; then
  echo ""
  echo "==> Checking for mas apps not in Brewfile..."
  # Brewfile(s) に記載されている mas ID を収集
  brewfile_ids=$(grep -h '^mas ' "$COMBINED" | grep -oE 'id: [0-9]+' | grep -oE '[0-9]+' || true)
  # インストール済み mas アプリと照合
  unmanaged=""
  while IFS= read -r line; do
    id=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | cut -d' ' -f2-)
    if ! echo "$brewfile_ids" | grep -qx "$id"; then
      unmanaged="${unmanaged}  $id  $name\n"
    fi
  done < <(mas list 2>/dev/null || true)
  if [[ -n "$unmanaged" ]]; then
    printf '%sWARNING: The following App Store apps are installed but not in Brewfile.%s\n' "$YELLOW" "$RESET" >&2
    printf '%s         brew bundle cleanup does not uninstall mas apps — remove them manually:%s\n' "$YELLOW" "$RESET" >&2
    printf "%b" "$unmanaged" >&2
    printf "%s         Run 'mas uninstall <id>' first, then 'dots brew cache' to update the cache.%s\n" "$YELLOW" "$RESET" >&2
  else
    echo "All installed mas apps are listed in Brewfile."
  fi
fi
