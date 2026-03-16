#!/usr/bin/env bash
set -euo pipefail
DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT="$DOTFILES_DIR/macos/dock-snapshot.txt"

# ── Dock アプリ一覧 ────────────────────────────────────────────────────────────
if command -v dockutil &>/dev/null; then
  dockutil --no-restart --remove all

  # ── 標準アプリ（2026-03-16 sync） ─────────────────────────────────────────────
  dockutil --no-restart --add "/System/Applications/Apps.app"
  dockutil --no-restart --add "/Applications/Canary Mail.app"
  dockutil --no-restart --add "/Applications/Microsoft Teams.app"
  dockutil --no-restart --add "/Applications/Brave Browser.app"
  dockutil --no-restart --add "/Applications/Rakuten Web Search.app"
  dockutil --no-restart --add "/Applications/iTerm.app"
  dockutil --no-restart --add "/Applications/Zotero.app"
  dockutil --no-restart --add "/Applications/Microsoft Word.app"
  dockutil --no-restart --add "/Applications/Microsoft Excel.app"
  dockutil --no-restart --add "/Applications/PyCharm.app"
  dockutil --no-restart --add "/Applications/wxmaxima.app"
  dockutil --no-restart --add "/Applications/Visual Studio Code.app"
  dockutil --no-restart --add "/Applications/Sublime Text.app"
  dockutil --no-restart --add "/Applications/UpNote.app"
  dockutil --no-restart --add "/Applications/Stickies Pro.app"
  dockutil --no-restart --add "/Applications/FortiToken.app"
  dockutil --no-restart --add "/Applications/PDF Expert.app"
  dockutil --no-restart --add "/System/Applications/Reminders.app"
  dockutil --no-restart --add "/Applications/ToDo.app"
  dockutil --no-restart --add "/Applications/Spotify.app"
  dockutil --no-restart --add "/System/Applications/System Settings.app"

  # ── Mac 固有の追加 ─────────────────────────────────────────────────────────────
  HOST_DOCK="$DOTFILES_DIR/host/$(hostname -s).dock.sh"
  # shellcheck source=/dev/null
  [ -f "$HOST_DOCK" ] && source "$HOST_DOCK"

  killall Dock 2>/dev/null || true
else
  echo "Warning: dockutil not found. Run: brew install dockutil" >&2
fi

# ── Finder サイドバー ──────────────────────────────────────────────────────────
if command -v mysides &>/dev/null; then
  # 既存エントリを全削除
  mysides list | awk '{print $1}' | while IFS= read -r name; do
    [ -n "$name" ] && mysides remove "$name" 2>/dev/null || true
  done

  mysides add "アプリケーション" "file:///Applications/"
  mysides add "Desktop"          "file:///Users/$USER/Desktop/"
  mysides add "Downloads"        "file:///Users/$USER/Downloads"
  mysides add "Documents"        "file:///Users/$USER/Documents/"
else
  echo "Warning: mysides not found. Run: brew install mysides" >&2
fi

# ── スナップショット更新 ────────────────────────────────────────────────────────
bash "$(dirname "$0")/dock-sync.sh" --snapshot-only
echo "Done. Snapshot saved to $SNAPSHOT"
