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
#   --no-cleanup（dots brew apply --no-prune）:
#     cleanupとmasの未管理アプリ確認を行わない（追加・更新のみ）。無人経路で使う
#   --prune-only（dots brew prune）:
#     インストールは行わず、cleanupとmasの未管理アプリ確認だけを行う
#   --dry-run:
#     何も変更しない。追加予定のエントリを表示し、cleanupは --force なし（一覧表示のみ）で実行する
#
# 使い方:
#   DOTFILES_DIR=~/dotfiles bash apply_brewfile.sh [--diff-only] [--no-cleanup] [--prune-only] [--dry-run] [--force]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
BREWFILE="$DOTFILES_DIR/macos/Brewfile"
BREWFILE_CACHE="$DOTFILES_DIR/macos/Brewfile.cache"
BREWFILE_LOCAL="$DOTFILES_DIR/macos/Brewfile.local"
FORCE=0
DIFF_ONLY=0
NO_CLEANUP=0
PRUNE_ONLY=0
DRY_RUN=0
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --diff-only) DIFF_ONLY=1 ;;
    --no-cleanup) NO_CLEANUP=1 ;;
    --prune-only) PRUNE_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "error: unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ $PRUNE_ONLY -eq 1 && $NO_CLEANUP -eq 1 ]]; then
  echo "error: --prune-only と --no-cleanup は同時に指定できません" >&2
  exit 1
fi
# --prune-only は差分判定を使わず、常に cleanup を確認する
[[ $PRUNE_ONLY -eq 0 ]] || DIFF_ONLY=0
# --dry-run では削除しない（brew bundle cleanup は --force なしだと一覧表示のみ）
[[ $DRY_RUN -eq 0 ]] || FORCE=0

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

if [[ $PRUNE_ONLY -eq 1 ]]; then
  echo "==> Skipping install (--prune-only)."
elif [[ $DIFF_ONLY -eq 1 ]]; then
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

  if [[ $missing_count -gt 0 && $DRY_RUN -eq 1 ]]; then
    echo "==> [dry-run] ${missing_count} missing Brewfile entries would be installed:"
    sed 's/^/  [dry-run] install  /' "$DELTA"
  elif [[ $missing_count -gt 0 ]]; then
    echo "==> Installing ${missing_count} missing Brewfile entries..."
    brew bundle install --file="$DELTA"
  else
    echo "==> No missing Brewfile entries."
  fi
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "==> [dry-run] brew bundle install (Brewfile / Brewfile.local の全件) は実行しません。"
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
if [[ $NO_CLEANUP -eq 1 ]]; then
  echo "==> Skipping cleanup (--no-prune: 未管理のパッケージは削除しません)."
elif [[ $DIFF_ONLY -eq 0 || $extra_count -gt 0 ]]; then
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
if [[ $NO_CLEANUP -eq 0 ]] && command -v mas &>/dev/null && [[ $DIFF_ONLY -eq 0 || $extra_count -gt 0 ]]; then
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
