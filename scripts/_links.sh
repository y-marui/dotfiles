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
  "terminal/ohmyposh/p10k-lean.json|${HOME}/.config/oh-my-posh/p10k-lean.json"
  "terminal/powershell/profile.ps1|${HOME}/.config/powershell/Microsoft.PowerShell_profile.ps1"
  "ai/AI_CONTEXT.md|${HOME}/.ai/AI_CONTEXT.md"
  "ai/AI_CONTEXT_CLI.md|${HOME}/.ai/AI_CONTEXT_CLI.md"
  "ai/claude/settings.json|${HOME}/.claude/settings.json"
  "ai/claude/CLAUDE.md|${HOME}/.claude/CLAUDE.md"
  "ai/claude/hooks/status.sh|${HOME}/.claude/hooks/status.sh"
  "ai/copilot/instructions.md|${HOME}/.copilot/copilot-instructions.md"
  "ai/gemini/GEMINI.md|${HOME}/.gemini/GEMINI.md"
  "bin/run-quiet|${HOME}/.local/bin/run-quiet"
  "bin/ghq-check|${HOME}/.local/bin/ghq-check"
)
