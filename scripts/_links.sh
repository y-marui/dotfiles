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
  "editor/vimrc|${HOME}/.vimrc"
  "terminal/tmux.conf|${HOME}/.tmux.conf"
  "terminal/p10k.zsh|${HOME}/.p10k.zsh"
  "ai/claude/settings.json|${HOME}/.claude/settings.json"
  "ai/claude/CLAUDE.md|${HOME}/.claude/CLAUDE.md"
  "ai/claude/statusline-command.sh|${HOME}/.claude/statusline-command.sh"
  "ai/claude/hooks/ntfy_notify.sh|${HOME}/.claude/hooks/ntfy_notify.sh"
  "ai/claude/hooks/status.sh|${HOME}/.claude/hooks/status.sh"
)
