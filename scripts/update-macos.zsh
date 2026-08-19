#!/usr/bin/env zsh
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

# tlmgr 等、途中で sudo が必要なコマンドのためにここで認証を済ませておく。
# バックグラウンドループでタイムスタンプを更新し続け、この後の sudo 呼び出しで
# 再度パスワード入力を求められないようにする（スクリプト終了時に自動停止）。
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

LOG_FILE=$(mktemp)
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null; rm -f "${LOG_FILE}"' EXIT

# 各コマンドの出力を画面にそのまま流しつつログにも残し、最後に
# warning/deprecated 行だけをまとめて再掲する。
log() { "$@" 2>&1 | tee -a "${LOG_FILE}"; }

# ask mode がデフォルトのため、deprecated/disabled パッケージ等を含むと
# 対話プロンプトで停止する。-y で確認をスキップし非対話実行を通す。
log brew update
log brew upgrade -y
log brew cleanup

# Zellij is intentionally managed outside Homebrew while the iTerm2 rendering
# compatibility issue is open. Re-assert the approved version on every update.
log bash "${0:A:h}/setup-zellij.sh"

log pipx upgrade-all

log npm update -g

log sudo tlmgr update --self --all

if command -v rbenv &>/dev/null && [[ "$(rbenv version-name 2>/dev/null)" != "system" ]]; then
  log gem update --system
  log gem update
  log gem cleanup
fi

log bash "${0:A:h}/update-prezto.sh"

log mas upgrade
log softwareupdate -i -a

log ghq-update --pull-all

echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') Warnings ==="
if grep -iE "warn|deprecat" "${LOG_FILE}" > /dev/null 2>&1; then
  grep -iE "warn|deprecat" "${LOG_FILE}"
else
  echo "(none)"
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
