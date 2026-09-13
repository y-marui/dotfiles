#!/usr/bin/env zsh
set -euo pipefail

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update started ==="

# tlmgr 等、途中で sudo が必要なコマンドのためにここで認証を済ませておく。
# バックグラウンドループでタイムスタンプを更新し続け、この後の sudo 呼び出しで
# 再度パスワード入力を求められないようにする（スクリプト終了時に自動停止）。
# サブシェルは親の `set -e` を継承するため、`sudo -n true` が一度でも失敗すると
# （スリープ/画面ロック等でタイムスタンプが無効化された場合等）ループごと即終了し、
# 以降二度と再試行されなくなる。`|| true` で単発の失敗をループ継続扱いにする。
sudo -v
( while true; do sudo -n true || true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

LOG_FILE=$(mktemp)
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null; rm -f "${LOG_FILE}"' EXIT

# 各コマンドの出力を画面にそのまま流しつつログにも残し、最後に
# warning/deprecated 行だけをまとめて再掲する。
log() { "$@" 2>&1 | tee -a "${LOG_FILE}"; }

# Brewfile-pinの一時除外を先に適用し、既知の不具合で全体更新が停止するのを防ぐ。
log bash "${0:A:h}/../macos/apply_brewpin.sh"

# ask mode がデフォルトのため、deprecated/disabled パッケージ等を含むと
# 対話プロンプトで停止する。-y で確認をスキップし非対話実行を通す。
log brew update
log brew upgrade -y
log brew cleanup

# Zellij is intentionally managed outside Homebrew while the iTerm2 rendering
# compatibility issue is open. Re-assert the approved version on every update.
log bash "${0:A:h}/setup-zellij.sh"

resolve_global_python() {
  local global_versions

  if command -v pyenv &>/dev/null; then
    # dots は任意のディレクトリから実行できるため、local .python-version や
    # PYENV_VERSION ではなく、pyenv global の選択を明示して解決する。
    global_versions="$(pyenv global | paste -sd: -)"
    PYENV_VERSION="${global_versions}" pyenv which python3
  else
    python3 -c 'import os, sys; print(os.path.realpath(sys.executable))'
  fi
}

PIPX_GLOBAL_PYTHON="$(resolve_global_python)"
PIPX_GLOBAL_PYTHON="$("${PIPX_GLOBAL_PYTHON}" -c 'import os, sys; print(os.path.realpath(sys.executable))')"
PIPX_GLOBAL_PYTHON_VERSION="$("${PIPX_GLOBAL_PYTHON}" -c 'import platform; print(platform.python_version())')"
PIPX_VENVS_DIR="$(pipx environment --value PIPX_HOME)/venvs"
PIPX_REINSTALL_ALL=false

for venv_dir in "${PIPX_VENVS_DIR}"/*; do
  [[ -d "${venv_dir}" ]] || continue

  venv_python="${venv_dir}/bin/python"
  if [[ ! -x "${venv_python}" ]]; then
    PIPX_REINSTALL_ALL=true
    break
  fi
  if ! venv_base_python="$("${venv_python}" -c 'import os, sys; print(os.path.realpath(getattr(sys, "_base_executable", sys.executable)))' 2>/dev/null)" || \
    ! venv_python_version="$("${venv_python}" -c 'import platform; print(platform.python_version())' 2>/dev/null)"; then
    PIPX_REINSTALL_ALL=true
    break
  fi
  if [[ "${venv_base_python}" != "${PIPX_GLOBAL_PYTHON}" || \
    "${venv_python_version}" != "${PIPX_GLOBAL_PYTHON_VERSION}" ]]; then
    PIPX_REINSTALL_ALL=true
    break
  fi
done

if [[ "${PIPX_REINSTALL_ALL}" == true ]]; then
  echo "  REINSTALL pipx environments with global Python ${PIPX_GLOBAL_PYTHON_VERSION}"
  log pipx reinstall-all --python "${PIPX_GLOBAL_PYTHON}"
else
  log pipx upgrade-all
fi

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
# ghq-pull/ghq-update/ghq-sweep は問題を "  [skip ...]"/"[warn]"/"[conflict]"/
# "[failed]" のタグ付き行で報告する（_ghq-lib.sh 参照）。"warn|deprecat" だけを
# 拾うと、これらタグ行の大半（[skip auto-pr] 等）が本節から漏れてしまうため、
# タグそのものにもマッチさせる。
if grep -iE "warn|deprecat|\[skip|\[conflict|\[failed" "${LOG_FILE}" > /dev/null 2>&1; then
  grep -iE "warn|deprecat|\[skip|\[conflict|\[failed" "${LOG_FILE}"
else
  echo "(none)"
fi

echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update completed ==="
