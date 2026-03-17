#!/usr/bin/env bash
set -euo pipefail

echo "Applying macOS defaults..."

# ── Finder ──────────────────────────────────────────────────────────────────
# 隠しファイルを非表示
defaults write com.apple.finder AppleShowAllFiles -bool false
# 拡張子を常に表示
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# パスバーを表示
defaults write com.apple.finder ShowPathbar -bool true
# ステータスバーを表示
defaults write com.apple.finder ShowStatusBar -bool true
# デフォルトビューをリストにする
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
# 検索時はカレントフォルダを対象にする
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# ── Dock ─────────────────────────────────────────────────────────────────────
# 自動的に隠す（手動変更時は dock.sh で管理）
defaults write com.apple.dock autohide -bool false
# 最近使ったアプリを表示しない
defaults write com.apple.dock show-recents -bool false
# アイコンサイズはデフォルト
# defaults write com.apple.dock tilesize -int 36

# ── キーボード ────────────────────────────────────────────────────────────────
# キーリピートを高速化
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# フルキーボードアクセスを有効化（Tab でボタン操作）
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# ── トラックパッド ────────────────────────────────────────────────────────────
# タップでクリックを有効化
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

# ── スクリーンショット ─────────────────────────────────────────────────────────
# 影を含めない
defaults write com.apple.screencapture disable-shadow -bool true
# PNG 形式で保存
defaults write com.apple.screencapture type -string "png"

# ── テキスト入力 ──────────────────────────────────────────────────────────────
# 自動大文字変換を無効化
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
# スマートダッシュを無効化
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
# スマートクォートを無効化
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
# スペル自動修正を無効化
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# ── iTerm2 ───────────────────────────────────────────────────────────────────
# dotfiles の terminal/iterm2/ から設定を読み込む
ITERM2_PREFS_DIR="$(cd "$(dirname "$0")/.." && pwd)/terminal/iterm2"
defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ITERM2_PREFS_DIR"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true

# ── 反映 ─────────────────────────────────────────────────────────────────────
echo "Restarting affected applications..."
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo "Done. Some changes may require a restart."
