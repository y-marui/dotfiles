#!/usr/bin/env zsh
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

# tlmgr 等、途中で sudo が必要なコマンドのためにここで認証を済ませておく。
# バックグラウンドループでタイムスタンプを更新し続け、この後の sudo 呼び出しで
# 再度パスワード入力を求められないようにする（スクリプト終了時に自動停止）。
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null' EXIT

# ask mode がデフォルトのため、deprecated/disabled パッケージ等を含むと
# 対話プロンプトで停止する。-y で確認をスキップし非対話実行を通す。
brew update
brew upgrade -y
brew cleanup

# Zellij is intentionally managed outside Homebrew while the iTerm2 rendering
# compatibility issue is open. Re-assert the approved version on every update.
bash "${0:A:h}/setup-zellij.sh"

pipx upgrade-all

npm update -g

sudo tlmgr update --self --all

if command -v rbenv &>/dev/null && [[ "$(rbenv version-name 2>/dev/null)" != "system" ]]; then
  gem update --system
  gem update
  gem cleanup
fi

bash "${0:A:h}/update-prezto.sh"

mas upgrade
softwareupdate -i -a

ghq-update --pull-all

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
