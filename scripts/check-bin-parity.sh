#!/usr/bin/env bash
set -euo pipefail

# scripts/check-bin-parity.sh
# bin/unix/ と bin/windows/ のカスタムコマンドの対応関係を検証する。
# 全コマンドは原則両OSに実装すること（AI_CONTEXT.md の「OS 別実装の方針」参照）。
# 片方専用と分かっているコマンドだけ EXCEPTIONS に理由付きで列挙する。

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIX_DIR="${DOTFILES_DIR}/bin/unix"
WINDOWS_DIR="${DOTFILES_DIR}/bin/windows"

# コマンド名 => 片方だけに存在してよい理由
declare -A EXCEPTIONS=(
  [install-my-apps]="macOS専用ツール（.appのDMGインストール）"
)

unix_cmds=()
for f in "${UNIX_DIR}"/*; do
  name="$(basename "${f}")"
  [[ "${name}" == _* ]] && continue
  unix_cmds+=("${name}")
done

windows_cmds=()
for f in "${WINDOWS_DIR}"/*.ps1; do
  name="$(basename "${f}" .ps1)"
  [[ "${name}" == _* ]] && continue
  windows_cmds+=("${name}")
done

_contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

missing_on_windows=()
for cmd in "${unix_cmds[@]}"; do
  [[ -n "${EXCEPTIONS[${cmd}]:-}" ]] && continue
  _contains "${cmd}" "${windows_cmds[@]}" || missing_on_windows+=("${cmd}")
done

missing_on_unix=()
for cmd in "${windows_cmds[@]}"; do
  [[ -n "${EXCEPTIONS[${cmd}]:-}" ]] && continue
  _contains "${cmd}" "${unix_cmds[@]}" || missing_on_unix+=("${cmd}")
done

# Windows側は *.ps1 と *.cmd（bareコマンド名で呼ぶための薄いシム）が対で必須
missing_cmd_wrapper=()
for f in "${WINDOWS_DIR}"/*.ps1; do
  name="$(basename "${f}" .ps1)"
  [[ "${name}" == _* ]] && continue
  [[ -f "${WINDOWS_DIR}/${name}.cmd" ]] || missing_cmd_wrapper+=("${name}")
done

status=0

if [[ ${#missing_on_windows[@]} -gt 0 ]]; then
  echo "エラー: bin/unix/ にあるが bin/windows/ に *.ps1 がありません: ${missing_on_windows[*]}" >&2
  status=1
fi

if [[ ${#missing_on_unix[@]} -gt 0 ]]; then
  echo "エラー: bin/windows/ にあるが bin/unix/ に対応するコマンドがありません: ${missing_on_unix[*]}" >&2
  status=1
fi

if [[ ${#missing_cmd_wrapper[@]} -gt 0 ]]; then
  echo "エラー: bin/windows/ で *.ps1 に対応する *.cmd がありません: ${missing_cmd_wrapper[*]}" >&2
  status=1
fi

if [[ "${status}" -eq 0 ]]; then
  echo "OK: bin/unix と bin/windows のコマンド対応に問題ありません（${#unix_cmds[@]}件）"
fi

exit "${status}"
