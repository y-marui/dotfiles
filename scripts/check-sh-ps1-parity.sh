#!/usr/bin/env bash
set -euo pipefail

# scripts/check-sh-ps1-parity.sh
# リポジトリ全体（bin/ を除く）で .sh と .ps1 の対応関係を検証する。
# bin/ のコマンド対応は scripts/check-bin-parity.sh が別途担当する
# （bin/unix は拡張子なし、bin/windows は *.ps1+*.cmd という命名規則が異なるため）。
#
# Windows 向けスクリプトは PowerShell でネイティブに実装する方針のため
# （AI_CONTEXT.md の「OS 別実装の方針」参照）、原則すべての .sh に対応する
# .ps1 を用意すること。OS 固有で片方にしか存在しないと分かっているファイルだけ、
# 理由付きで EXCEPTIONS に列挙する。

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 相対パス（.sh または .ps1）:対応するスクリプトが不要な理由
# bash 3.2（macOS標準）は連想配列(declare -A)未対応のため key:value 文字列で代用
EXCEPTIONS=(
  "macos/apply_brewpin.sh:macOS専用（Homebrew）"
  "macos/apply_brewfile.sh:macOS専用（Homebrew）"
  "macos/apply_dockfile.sh:macOS専用（Dock）"
  "macos/apply_keyboard_shortcuts.sh:macOS専用（アプリケーションショートカット）"
  "macos/defaults.sh:macOS専用（macOS defaults）"
  "macos/diff_brewpin.sh:macOS専用（Homebrew）"
  "macos/diff_brewfile.sh:macOS専用（Homebrew）"
  "macos/diff_dockfile.sh:macOS専用（Dock）"
  "macos/diff_keyboard_shortcuts.sh:macOS専用（アプリケーションショートカット）"
  "macos/dots-check-monitor.sh:macOS専用（LaunchAgent・通知）"
  "macos/merge_keyboard_shortcuts.sh:macOS専用（アプリケーションショートカット）"
  "macos/sync_brewfile.sh:macOS専用（Homebrew）"
  "macos/sync_dockfile.sh:macOS専用（Dock）"
  "macos/sync_keyboard_shortcuts.sh:macOS専用（アプリケーションショートカット）"
  "macos/setup_dots_check_launchagent.sh:macOS専用（LaunchAgent）"
  "macos/update_brewpin_cache.sh:macOS専用（Homebrew）"
  "macos/update_brewcache.sh:macOS専用（Homebrew）"
  "macos/update_dockcache.sh:macOS専用（Dock）"
  "macos/update_keyboard_shortcuts_cache.sh:macOS専用（アプリケーションショートカット）"
  "rpi/apply_packages.sh:Raspberry Pi専用"
  "rpi/setup_gpg_agent.sh:Raspberry Pi専用"
  "rpi/repos/setup_claude-code.sh:Raspberry Pi専用"
  "rpi/repos/setup_homebridge.sh:Raspberry Pi専用"
  "rpi/repos/setup_tailscale.sh:Raspberry Pi専用"
  "rpi/setup_zellij.sh:Raspberry Pi専用"
  "rpi/setup_zsh.sh:Raspberry Pi専用"
  "scripts/setup-prezto.sh:zpreztoはWindowsで未使用"
  "scripts/update-prezto.sh:zpreztoはWindowsで未使用"
  "scripts/update-rpi-homebridge.sh:Raspberry Pi専用"
  "scripts/check-bin-parity.sh:pre-commit専用ツール。git-bash経由で全OS共通実行"
  "scripts/check-sh-ps1-parity.sh:pre-commit専用ツール。git-bash経由で全OS共通実行"
  "scripts/check-skills.sh:make専用ツール。git-bash経由で全OS共通実行"
  "scripts/check-ai-context-reference.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-charter-ci-template.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-charter-subtree-edit.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-conventional-commit.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-dotenv-gitignore.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-language-pair-footer.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-language-pair-sync.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-license-exists.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-local-charter-version.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-markdown-heading-language.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-python-package-management.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/check-readme-placeholders.sh:dev-charterのpre-commitフック。git-bash経由で全OS共通実行"
  "scripts/init-host.sh:make専用ツール。git-bash経由で全OS共通実行"
  "scripts/setup-private.sh:make専用ツール（gh CLI依存）。git-bash経由で全OS共通実行"
  "scripts/run_quiet_hook.sh:Claude Codeフックはbash経由で実行される前提のためOS問わず動作"
  "ai/claude/hooks/status.sh:Claude Codeのstatuslineはbash経由で実行される前提のためOS問わず動作"
  "ai/claude/mcp/apply.sh:TODO: dots.ps1がclaudeサブコマンド未実装のため未移植"
  "ai/claude/mcp/diff.sh:TODO: dots.ps1がclaudeサブコマンド未実装のため未移植"
  "ai/claude/mcp/prune.sh:TODO: dots.ps1がclaudeサブコマンド未実装のため未移植"
  "ai/claude/plugin/apply.sh:TODO: dots.ps1がclaudeサブコマンド未実装のため未移植"
  "ai/claude/plugin/diff.sh:TODO: dots.ps1がclaudeサブコマンド未実装のため未移植"
  "ai/claude/plugin/prune.sh:TODO: dots.ps1がclaudeサブコマンド未実装のため未移植"
  "ai/codex/mcp/apply.sh:TODO: dots.ps1がcodexサブコマンド未実装のため未移植"
  "ai/codex/mcp/diff.sh:TODO: dots.ps1がcodexサブコマンド未実装のため未移植"
  "ai/codex/mcp/prune.sh:TODO: dots.ps1がcodexサブコマンド未実装のため未移植"
  "ai/codex/plugin/apply.sh:TODO: dots.ps1がcodexサブコマンド未実装のため未移植"
  "ai/codex/plugin/diff.sh:TODO: dots.ps1がcodexサブコマンド未実装のため未移植"
  "ai/codex/plugin/prune.sh:TODO: dots.ps1がcodexサブコマンド未実装のため未移植"
  "ai/copilot/mcp/apply.sh:TODO: dots.ps1がcopilotサブコマンド未実装のため未移植"
  "ai/copilot/mcp/diff.sh:TODO: dots.ps1がcopilotサブコマンド未実装のため未移植"
  "ai/copilot/mcp/prune.sh:TODO: dots.ps1がcopilotサブコマンド未実装のため未移植"
  "ai/gemini/mcp/apply.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/gemini/mcp/diff.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/gemini/mcp/prune.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/gemini/mcp/run-github-mcp.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/gemini/plugin/apply.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/gemini/plugin/diff.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/gemini/plugin/prune.sh:TODO: dots.ps1がgeminiサブコマンド未実装のため未移植"
  "ai/skills/apply.sh:TODO: dots.ps1がskillサブコマンド未実装のため未移植"
  "ai/skills/diff.sh:TODO: dots.ps1がskillサブコマンド未実装のため未移植"
  "ai/skills/prune.sh:TODO: dots.ps1がskillサブコマンド未実装のため未移植"
  "npm/apply_npmfile.sh:TODO: dots.ps1がnpmサブコマンド未実装のため未移植"
  "npm/diff_npmfile.sh:TODO: dots.ps1がnpmサブコマンド未実装のため未移植"
  "npm/sync_npmfile.sh:TODO: dots.ps1がnpmサブコマンド未実装のため未移植"
  "npm/update_npmcache.sh:TODO: dots.ps1がnpmサブコマンド未実装のため未移植"
  "pipx/apply_pipxfile.sh:TODO: dots.ps1がpipxサブコマンド未実装のため未移植"
  "pipx/diff_pipxfile.sh:TODO: dots.ps1がpipxサブコマンド未実装のため未移植"
  "pipx/sync_pipxfile.sh:TODO: dots.ps1がpipxサブコマンド未実装のため未移植"
  "pipx/update_pipxcache.sh:TODO: dots.ps1がpipxサブコマンド未実装のため未移植"
  "scripts/setup-gsudo.ps1:gsudoはWindows専用ツールのセットアップ"
  "scripts/setup-jq.ps1:jqの導入はWindowsのみ自動化（macOSはBrewfileでbrewが管理）"
  "scripts/update-windows.ps1:Windows専用の追加更新処理。役割の異なるOS別スクリプト（update-rpi-homebridge.sh等）に相当するため対のunix実装なし"
  "terminal/powershell/profile.ps1:PowerShellプロファイル本体。zshrc等と役割が異なる設定ファイルのため対応不要"
  "windows/apply_wingetpin.ps1:Windows専用（winget）。macOSのBrewfile-pin相当だがパッケージマネージャーが異なるため対のunix実装なし"
  "windows/diff_wingetpin.ps1:Windows専用（winget）。macOSのBrewfile-pin相当だがパッケージマネージャーが異なるため対のunix実装なし"
  "windows/update_wingetpin_cache.ps1:Windows専用（winget）。macOSのBrewfile-pin相当だがパッケージマネージャーが異なるため対のunix実装なし"
)

_exception_key() {
  printf '%s' "${1%%:*}"
}

_is_exception() {
  local needle="$1" entry
  for entry in "${EXCEPTIONS[@]}"; do
    [[ "$(_exception_key "${entry}")" == "${needle}" ]] && return 0
  done
  return 1
}

missing_ps1=()
while IFS= read -r -d '' f; do
  rel="${f#./}"
  [[ "${rel}" == bin/* ]] && continue
  _is_exception "${rel}" && continue
  ps1="${rel%.sh}.ps1"
  [[ -f "${DOTFILES_DIR}/${ps1}" ]] || missing_ps1+=("${rel}")
done < <(cd "${DOTFILES_DIR}" && find . -name "*.sh" -not -path "./.git/*" -not -path "./.venv/*" -print0)

missing_sh=()
while IFS= read -r -d '' f; do
  rel="${f#./}"
  [[ "${rel}" == bin/* ]] && continue
  _is_exception "${rel}" && continue
  sh="${rel%.ps1}.sh"
  [[ -f "${DOTFILES_DIR}/${sh}" ]] || missing_sh+=("${rel}")
done < <(cd "${DOTFILES_DIR}" && find . -name "*.ps1" -not -path "./.git/*" -not -path "./.venv/*" -print0)

# EXCEPTIONS に列挙されているが実在しない、または不要になったパスを検出
# （ファイルの削除・移動時の登録漏れ防止）
stale=()
for entry in "${EXCEPTIONS[@]}"; do
  rel="$(_exception_key "${entry}")"
  [[ -f "${DOTFILES_DIR}/${rel}" ]] || stale+=("${rel}")
done

status=0

if [[ ${#missing_ps1[@]} -gt 0 ]]; then
  echo "エラー: 対応する .ps1 がありません（不要なら scripts/check-sh-ps1-parity.sh のEXCEPTIONSに理由付きで追加）:" >&2
  printf '  %s\n' "${missing_ps1[@]}" >&2
  status=1
fi

if [[ ${#missing_sh[@]} -gt 0 ]]; then
  echo "エラー: 対応する .sh がありません（不要なら scripts/check-sh-ps1-parity.sh のEXCEPTIONSに理由付きで追加）:" >&2
  printf '  %s\n' "${missing_sh[@]}" >&2
  status=1
fi

if [[ ${#stale[@]} -gt 0 ]]; then
  echo "エラー: EXCEPTIONS に存在しないパスが登録されています（削除または修正してください）:" >&2
  printf '  %s\n' "${stale[@]}" >&2
  status=1
fi

if [[ "${status}" -eq 0 ]]; then
  echo "OK: .sh と .ps1 の対応に問題ありません"
fi

exit "${status}"
