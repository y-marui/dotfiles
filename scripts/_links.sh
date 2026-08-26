# shellcheck shell=bash
# scripts/_links.sh
# install.sh / uninstall.sh / check.sh から source される。

# shellcheck disable=SC2034  # sourced ファイルなので未使用扱いになるが意図的
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC2034
LINKS=(
  "shell/profile|${HOME}/.profile"
  "shell/zshenv|${HOME}/.zshenv"
  "shell/zshrc|${HOME}/.zshrc"
  "shell/zprofile|${HOME}/.zprofile"
  "shell/zlogin|${HOME}/.zlogin"
  "shell/zlogout|${HOME}/.zlogout"
  "shell/zpreztorc|${HOME}/.zpreztorc"
  "shell/bashrc|${HOME}/.bashrc"
  "shell/bash_profile|${HOME}/.bash_profile"
  "git/gitconfig|${HOME}/.gitconfig"
  "git/gitignore_global|${HOME}/.gitignore_global"
  "git/hooks|${HOME}/.config/git/hooks"
  "terminal/zellij/config.kdl|${HOME}/.config/zellij/config.kdl"
  "terminal/p10k.zsh|${HOME}/.p10k.zsh"
  "ai/AI_CONTEXT.md|${HOME}/.ai/AI_CONTEXT.md"
  "ai/AI_CONTEXT_CLI.md|${HOME}/.ai/AI_CONTEXT_CLI.md"
  "ai/AI_CONTEXT.md|${HOME}/.codex/AGENTS.md"
  "ai/claude/settings.json|${HOME}/.claude/settings.json"
  "ai/claude/CLAUDE.md|${HOME}/.claude/CLAUDE.md"
  "ai/claude/hooks/status.sh|${HOME}/.claude/hooks/status.sh"
  "ai/copilot/instructions.md|${HOME}/.copilot/copilot-instructions.md"
  "ai/gemini/GEMINI.md|${HOME}/.gemini/GEMINI.md"
  "completions|${HOME}/.zsh_completions"
  "bin/unix|${HOME}/.local/bin/dotfiles"
)

# OS 別 git 設定（credential.helper 等）。macOS でのみ ~/.gitconfig.d/os としてリンクする。
if [[ "$(uname -s)" == "Darwin" ]]; then
  LINKS+=("git/gitconfig.d/macos.gitconfig|${HOME}/.gitconfig.d/os")

  # Karabiner-Elements（macOS 専用）。karabiner.json はアプリが Preferences 保存や
  # デバイス接続時に atomic rename で書き換えるため、シンボリックリンクが実ファイルに
  # 置き換わり同期が切れることがある。切れた場合は make links で再リンクする。
  LINKS+=(
    "karabiner/karabiner.json|${HOME}/.config/karabiner/karabiner.json"
    "karabiner/complex_modifications/rdp-jis.json|${HOME}/.config/karabiner/assets/complex_modifications/rdp-jis.json"
    "macos/dots-check-monitor.sh|${HOME}/.local/bin/dots-check-monitor"
    "macos/com.y-marui.dotfiles-check.plist|${HOME}/Library/LaunchAgents/com.y-marui.dotfiles-check.plist"
  )
fi

# 共通 skill と agent 専用 skill はディレクトリ全体ではなく、SKILL.md を持つものだけを
# 個別リンクする。これにより、アプリや CLI が追加した未管理 skill と所有範囲が衝突しない。
CODEX_LEGACY_SKILLS=()
for agent in codex claude; do
  case "${agent}" in
    codex) skill_home="${HOME}/.agents/skills" ;;
    claude) skill_home="${HOME}/.claude/skills" ;;
  esac

  seen_skill_names="|"
  for source_home in "${DOTFILES_DIR}/ai/skills" "${DOTFILES_DIR}/ai/${agent}/skills"; do
    for skill_file in "${source_home}/"*/SKILL.md; do
      [[ -e "${skill_file}" ]] || continue
      skill_dir="$(dirname "${skill_file}")"
      skill_name="$(basename "${skill_dir}")"
      if [[ "${seen_skill_names}" == *"|${skill_name}|"* ]]; then
        printf '共通 skill と %s 専用 skill で名前が重複しています: %s\n' \
          "${agent}" "${skill_name}" >&2
        return 1
      fi
      seen_skill_names="${seen_skill_names}${skill_name}|"
      skill_source="${skill_dir#"${DOTFILES_DIR}/"}"
      LINKS+=("${skill_source}|${skill_home}/${skill_name}")
      if [[ "${agent}" == codex ]]; then
        CODEX_LEGACY_SKILLS+=("${skill_name}")
      fi
    done
  done
done

# ~/.codex/skills は Codex 自身や skill-installer の管理領域。管理対象と同名の
# skill がある場合だけ、~/.agents/skills との二重読み込みを避けるためバックアップする。
