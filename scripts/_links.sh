# shellcheck shell=bash
# scripts/_links.sh
# install.sh / uninstall.sh / check.sh から source される。

# shellcheck disable=SC2034  # sourced ファイルなので未使用扱いになるが意図的
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="${DOTFILES_DIR}-private"

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
  "ai/codex/AGENTS.md|${HOME}/.codex/AGENTS.md"
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
  LINKS+=(
    "git/gitconfig.d/macos.gitconfig|${HOME}/.gitconfig.d/os"
    "macos/profile|${HOME}/.profile.macos"
  )

  # Karabiner-Elements（macOS 専用）。karabiner.json はアプリが Preferences 保存や
  # デバイス接続時に atomic rename で書き換えるため、シンボリックリンクが実ファイルに
  # 置き換わり同期が切れることがある。切れた場合は make links で再リンクする。
  LINKS+=(
    "karabiner/karabiner.json|${HOME}/.config/karabiner/karabiner.json"
    "karabiner/complex_modifications/rdp-jis.json|${HOME}/.config/karabiner/assets/complex_modifications/rdp-jis.json"
    "macos/dots-check-monitor.sh|${HOME}/.local/bin/dots-check-monitor"
    "macos/dots-check-monitor-popup.sh|${HOME}/.local/bin/dots-check-monitor-popup"
    "macos/com.y-marui.dotfiles-check.plist|${HOME}/Library/LaunchAgents/com.y-marui.dotfiles-check.plist"
    "macos/museum-status-refresh.sh|${HOME}/.local/bin/museum-status-refresh"
    "macos/com.y-marui.museum-status-refresh.plist|${HOME}/Library/LaunchAgents/com.y-marui.museum-status-refresh.plist"
  )
fi

# 共通 skill と agent 専用 skill はディレクトリ全体ではなく、SKILL.md を持つものだけを
# 個別リンクする。これにより、アプリや CLI が追加した未管理 skill と所有範囲が衝突しない。
# gemini は Antigravity と Gemini CLI 本体で参照先ディレクトリが異なるため、
# agent 1つにつき複数の配置先を持てるよう skill_homes を配列にしている。
CODEX_LEGACY_SKILLS=()
for agent in codex claude gemini; do
  case "${agent}" in
    codex) skill_homes=("${HOME}/.agents/skills") ;;
    claude) skill_homes=("${HOME}/.claude/skills") ;;
    gemini) skill_homes=("${HOME}/.gemini/skills" "${HOME}/.gemini/config/skills") ;;
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
      for skill_home in "${skill_homes[@]}"; do
        LINKS+=("${skill_source}|${skill_home}/${skill_name}")
      done
      if [[ "${agent}" == codex ]]; then
        CODEX_LEGACY_SKILLS+=("${skill_name}")
      fi
    done
  done
done

# ~/.codex/skills は Codex 自身や skill-installer の管理領域。管理対象と同名の
# skill がある場合だけ、~/.agents/skills との二重読み込みを避けるためバックアップする。

# dotfiles-private は設定データとリンク対応表だけを保持し、リンク操作の実装は
# dotfiles 側が所有する。対応表はシェルコードとして source せず、区切り形式として厳格に読む。
PRIVATE_LINKS=()
PRIVATE_INACTIVE_LINKS=()
PRIVATE_LINKS_FILE="${PRIVATE_DIR}/links.conf"
PRIVATE_LINK_DESTINATIONS=$'\n'

_private_link_path_is_valid() {
  local path="$1"

  [[ -n "${path}" ]] || return 1
  [[ "${path}" != /* && "${path}" != "~"* ]] || return 1
  [[ "${path}" != *\\* && "${path}" != *:* ]] || return 1
  [[ "/${path}/" != *"/../"* && "/${path}/" != *"/./"* ]] || return 1
}

_trim_private_link_field() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

_private_link_destination_is_unique() {
  local destination="$1"
  local entry existing_destination

  for entry in "${LINKS[@]}"; do
    existing_destination="${entry##*|}"
    if [[ "${existing_destination}" == "${destination}" ]]; then
      return 1
    fi
  done
  [[ "${PRIVATE_LINK_DESTINATIONS}" != *$'\n'"${destination}"$'\n'* ]]
}

_load_private_links() {
  local platform source_relative destination_relative extra source destination entry
  local system_name current_platform line_number=0 active=false

  [[ -d "${PRIVATE_DIR}" ]] || return 0
  if [[ ! -f "${PRIVATE_LINKS_FILE}" ]]; then
    echo "エラー: ${PRIVATE_LINKS_FILE} が見つかりません。dotfiles-private を更新してください。" >&2
    return 1
  fi

  system_name="$(uname -s)"
  case "${system_name}" in
    Darwin) current_platform="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) current_platform="windows" ;;
    *) current_platform="unix" ;;
  esac

  while IFS='|' read -r platform source_relative destination_relative extra || \
    [[ -n "${platform}${source_relative}${destination_relative}${extra}" ]]; do
    (( line_number++ )) || true
    platform="${platform%$'\r'}"
    source_relative="${source_relative%$'\r'}"
    destination_relative="${destination_relative%$'\r'}"
    extra="${extra%$'\r'}"
    platform="$(_trim_private_link_field "${platform}")"
    source_relative="$(_trim_private_link_field "${source_relative}")"
    destination_relative="$(_trim_private_link_field "${destination_relative}")"
    extra="$(_trim_private_link_field "${extra}")"

    [[ -n "${platform}${source_relative}${destination_relative}${extra}" ]] || continue
    [[ "${platform}" != \#* ]] || continue

    if [[ -n "${extra}" || -z "${source_relative}" || -z "${destination_relative}" ]]; then
      echo "エラー: ${PRIVATE_LINKS_FILE}:${line_number}: platform|source|destination の3列ではありません。" >&2
      return 1
    fi
    case "${platform}" in
      all|unix|darwin|windows) ;;
      *)
        echo "エラー: ${PRIVATE_LINKS_FILE}:${line_number}: 未対応platform: ${platform}" >&2
        return 1
        ;;
    esac
    if ! _private_link_path_is_valid "${source_relative}" || \
      ! _private_link_path_is_valid "${destination_relative}"; then
      echo "エラー: ${PRIVATE_LINKS_FILE}:${line_number}: 相対パスが不正です。" >&2
      return 1
    fi

    source="${PRIVATE_DIR}/${source_relative}"
    destination="${HOME}/${destination_relative}"
    if [[ ! -e "${source}" && ! -L "${source}" ]]; then
      echo "エラー: ${PRIVATE_LINKS_FILE}:${line_number}: sourceが存在しません: ${source_relative}" >&2
      return 1
    fi
    if ! _private_link_destination_is_unique "${destination}"; then
      echo "エラー: ${PRIVATE_LINKS_FILE}:${line_number}: destinationが重複しています: ${destination_relative}" >&2
      return 1
    fi
    PRIVATE_LINK_DESTINATIONS+="${destination}"$'\n'

    active=false
    case "${platform}" in
      all) active=true ;;
      unix) [[ "${current_platform}" != "windows" ]] && active=true ;;
      darwin) [[ "${current_platform}" == "darwin" ]] && active=true ;;
      windows) [[ "${current_platform}" == "windows" ]] && active=true ;;
    esac

    entry="${source_relative}|${destination}"
    if [[ "${active}" == true ]]; then
      PRIVATE_LINKS+=("${entry}")
    else
      PRIVATE_INACTIVE_LINKS+=("${entry}")
    fi
  done < "${PRIVATE_LINKS_FILE}"
}

_load_private_links
