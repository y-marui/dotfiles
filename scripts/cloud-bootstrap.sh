#!/usr/bin/env bash
# Claude Code のクラウドセッション（Linux VM）へ、dotfiles の AI 設定だけを展開する。
# 設計と運用手順は docs/cloud-sessions.md を参照する。
#
# Usage:
#   cloud-bootstrap.sh setup     環境の Setup script から呼ぶ。トークン不要の展開と、SessionStart フックの登録
#   cloud-bootstrap.sh session   SessionStart フックから呼ぶ。更新、private/vault の取得、環境変数の注入
#
# どちらのモードも、失敗してもセッションの起動を止めないよう常に終了コード 0 で終わる。
# 失敗は警告として stdout（セッションの文脈）とログに残す。トークンの値は出力しない。

set -euo pipefail

MODE="${1:-}"
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="${DOTFILES_DIR}-private"
VAULT_DIR="${CLOUD_VAULT_DIR:-${HOME}/src/github.com/y-marui/obsidian-vault}"
GIT_BASE="${CLOUD_GIT_BASE:-https://github.com}"
SELECT_FILE="${DOTFILES_DIR}/ai/skills/cloud-code.json"
LOG_FILE="${HOME}/.cache/cloud-bootstrap.log"

WARNINGS=()
STATUS=()

mkdir -p "$(dirname "${LOG_FILE}")"

log() {
  printf '%s\n' "$*" >> "${LOG_FILE}"
}

warn() {
  WARNINGS+=("$1")
  log "WARN: $1"
}

# timeout が無い環境（macOS のテスト実行など）では素通しする。
run_limited() {
  local seconds="$1"
  shift
  if command -v timeout > /dev/null 2>&1; then
    timeout "${seconds}" "$@"
  else
    "$@"
  fi
}

# 環境変数 $1 に入った PAT を、URL やログに出さず credential helper 経由で渡す。
git_with_token() {
  local var="$1"
  shift
  # helper の本文は git が sh で評価するため、ここでは展開しない。
  # shellcheck disable=SC2016
  CB_TOKEN="${!var}" GIT_TERMINAL_PROMPT=0 run_limited 300 git \
    -c credential.helper='!f() { echo username=x-access-token; echo "password=${CB_TOKEN}"; }; f' "$@"
}

# 取得後のリポジトリには、トークン値ではなく環境変数名を参照する helper を残す。
# 次回の pull で使う。push には使えない: Git プロキシは、セッションの sources に無い
# リポジトリへ認証情報を付けない。vault へ書くときは add_repo で追加する（docs/cloud-sessions.md）。
set_repo_credential_helper() {
  local dir="$1" var="$2"
  git -C "${dir}" config credential.helper \
    "!f() { echo username=x-access-token; echo \"password=\${${var}}\"; }; f"
}

# sync_repo <dir> <repo> <token-env-var> [clone-option...]
sync_repo() {
  local dir="$1" repo="$2" var="$3"
  shift 3
  # 呼び出し側が if 文の条件で使うと set -e が効かないため、失敗は && で明示的に伝える。
  if [[ -d "${dir}/.git" ]]; then
    git_with_token "${var}" -C "${dir}" pull --ff-only --quiet >> "${LOG_FILE}" 2>&1 \
      && set_repo_credential_helper "${dir}" "${var}"
  else
    mkdir -p "$(dirname "${dir}")" \
      && git_with_token "${var}" clone --quiet "$@" "${GIT_BASE}/${repo}.git" "${dir}" >> "${LOG_FILE}" 2>&1 \
      && set_repo_credential_helper "${dir}" "${var}"
  fi
}

# クラウドの vault clone に pre-push フックを置き、ai/cloud/* 以外への push を拒否する。
# GitHub 側の強制ではなく、事故を防ぐための VM 内のガード（クラウドの push は手元と同じ
# GitHub アカウントの認証情報で行われ、ruleset では手元とクラウドを区別できないため）。
install_vault_guard() {
  local hook="$1/.git/hooks/pre-push"
  mkdir -p "$(dirname "${hook}")"
  # グローバルな core.hooksPath があっても、この clone ではこのフックが効くようにする。
  git -C "$1" config core.hooksPath "$1/.git/hooks"
  cat > "${hook}" <<'HOOK'
#!/bin/sh
# cloud-bootstrap.sh が配置する。クラウドセッションからは ai/cloud/* だけに push できる。
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  case "${remote_ref}" in
    refs/heads/ai/cloud/*) ;;
    *)
      echo "pre-push: cloud sessions may push only to ai/cloud/* (got ${remote_ref})" >&2
      exit 1
      ;;
  esac
done
exit 0
HOOK
  chmod +x "${hook}"
}

link_one() {
  local src="$1" dest="$2"
  [[ -e "${src}" ]] || return 0
  mkdir -p "$(dirname "${dest}")"
  if [[ -e "${dest}" && ! -L "${dest}" ]]; then
    mv "${dest}" "${dest}.cloud-orig"
    log "BACKUP ${dest} -> ${dest}.cloud-orig"
  fi
  ln -sfn "${src}" "${dest}"
}

# ~/.ai、~/.claude/CLAUDE.md、bin、~/.identity だけを張る。シェル・git・ssh・terminal の
# 設定は、クラウド VM の挙動（commit 時の identity など）を壊すため対象にしない。
link_config() {
  (
    # shellcheck source=scripts/_links.sh
    source "${DOTFILES_DIR}/scripts/_links.sh"
    local entry src dest
    for entry in "${LINKS[@]}"; do
      src="${DOTFILES_DIR}/${entry%%|*}"
      dest="${entry##*|}"
      case "${dest}" in
        "${HOME}/.ai/"* | "${HOME}/.claude/CLAUDE.md" | "${HOME}/.local/bin/dotfiles")
          link_one "${src}" "${dest}"
          ;;
      esac
    done
    for entry in ${PRIVATE_LINKS[@]+"${PRIVATE_LINKS[@]}"}; do
      src="${PRIVATE_DIR}/${entry%%|*}"
      dest="${entry##*|}"
      case "${dest}" in
        "${HOME}/.identity/"*) link_one "${src}" "${dest}" ;;
      esac
    done
    link_one "${DOTFILES_DIR}/ai/claude/rules/cloud-environment.md" \
      "${HOME}/.claude/rules/cloud-environment.md"
  ) >> "${LOG_FILE}" 2>&1
}

# cloud-code.json から外された skill のリンクを消す。キャッシュ済みのスナップショットに
# 古いリンクが残ると、一覧から外したはずの skill が使えてしまうため。
# dotfiles が作ったリンク（指す先が ai/ 配下か外部 skill のキャッシュ）だけを対象にする。
prune_skills() {
  local skills_home="${HOME}/.claude/skills" cache_home link name target
  cache_home="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/skills"
  command -v jq > /dev/null 2>&1 || return 0
  for link in "${skills_home}"/*; do
    [[ -L "${link}" ]] || continue
    name="$(basename "${link}")"
    target="$(readlink "${link}")"
    case "${target}" in
      "${DOTFILES_DIR}/ai/"* | "${cache_home}/"*) ;;
      *) continue ;;
    esac
    if ! jq -e --arg n "${name}" '.skills | index($n)' "${SELECT_FILE}" > /dev/null 2>&1; then
      rm -f "${link}"
      log "PRUNE ${link}"
    fi
  done
}

link_skills() {
  SKILL_SELECT_FILE="${SELECT_FILE}" \
    bash "${DOTFILES_DIR}/ai/skills/apply.sh" claude >> "${LOG_FILE}" 2>&1 || return 1
  prune_skills
}

# ~/.claude/settings.json の SessionStart に、このスクリプトの session を登録する。
# 既存のフックは、同じ matcher 内の他のコマンドも含めて残し、この登録だけを置き換える
# （何度実行しても重複しない）。
register_hook() {
  local settings="${HOME}/.claude/settings.json" tmp command
  command="bash \"${DOTFILES_DIR}/scripts/cloud-bootstrap.sh\" session"
  mkdir -p "$(dirname "${settings}")"
  [[ -s "${settings}" ]] || printf '{}\n' > "${settings}"
  tmp="$(mktemp "${settings}.XXXXXX")"
  jq --arg cmd "${command}" '
    .hooks.SessionStart = (
      [(.hooks.SessionStart // [])[]
        | .hooks = [(.hooks // [])[] | select(((.command // "") | contains("cloud-bootstrap.sh")) | not)]
        | select((.hooks | length) > 0)]
      + [{matcher: "startup|resume", hooks: [{type: "command", command: $cmd, timeout: 300}]}]
    )' "${settings}" > "${tmp}" && mv "${tmp}" "${settings}" || { rm -f "${tmp}"; return 1; }
}

run_setup() {
  command -v jq > /dev/null 2>&1 || warn "jq が無いため SessionStart フックを登録できません"
  link_config || warn "設定のリンクに失敗しました"
  link_skills || warn "skill の展開に失敗しました"
  if command -v jq > /dev/null 2>&1; then
    register_hook || warn "SessionStart フックの登録に失敗しました"
  fi
}

run_session() {
  # 自分自身を含む dotfiles を更新したら、更新後のスクリプトで実行し直す。
  if [[ -z "${CLOUD_BOOTSTRAP_REEXEC:-}" ]]; then
    run_limited 120 git -C "${DOTFILES_DIR}" pull --ff-only --quiet >> "${LOG_FILE}" 2>&1 \
      || log "WARN: dotfiles を更新できませんでした（取得済みの版で続行）"
    CLOUD_BOOTSTRAP_REEXEC=1 exec bash "${BASH_SOURCE[0]}" session
  fi

  # 起動時と復元時のどちらで走ったかを、ログから判別できるようにする。
  log "== session $(date -u +%FT%TZ) =="

  if [[ -n "${DOTFILES_PRIVATE_TOKEN:-}" ]]; then
    if sync_repo "${PRIVATE_DIR}" "y-marui/dotfiles-private" DOTFILES_PRIVATE_TOKEN --depth 1; then
      STATUS+=("private=ok")
    else
      warn "dotfiles-private を取得できませんでした（~/.identity を使う skill は動きません）"
      STATUS+=("private=failed")
    fi
  else
    warn "DOTFILES_PRIVATE_TOKEN が未設定です（dotfiles-private を取得しません）"
    STATUS+=("private=skipped")
  fi

  if [[ -n "${VAULT_TOKEN:-}" ]]; then
    if sync_repo "${VAULT_DIR}" "y-marui/obsidian-vault" VAULT_TOKEN --filter=blob:none; then
      install_vault_guard "${VAULT_DIR}"
      STATUS+=("vault=ok")
    else
      warn "obsidian-vault を取得できませんでした（Project Home への記録は動きません）"
      STATUS+=("vault=failed")
    fi
  else
    STATUS+=("vault=skipped")
  fi

  link_config || warn "設定のリンクに失敗しました"
  link_skills || warn "skill の展開に失敗しました"

  if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    {
      printf 'export DOTFILES_DIR=%q\n' "${DOTFILES_DIR}"
      printf 'export PATH=%q\n' "${HOME}/.local/bin/dotfiles:${PATH}"
      if [[ -d "${VAULT_DIR}/.git" ]]; then
        printf 'export OBSIDIAN_VAULT_ROOT=%q\n' "${VAULT_DIR}"
      fi
    } >> "${CLAUDE_ENV_FILE}"
  fi
}

case "${MODE}" in
  setup) run_setup ;;
  session) run_session ;;
  *)
    printf 'usage: %s {setup|session}\n' "$0" >&2
    exit 2
    ;;
esac

# SessionStart の標準出力はセッションの文脈に入る。要点を1行だけ出す。
if [[ "${MODE}" == "session" ]]; then
  printf '[cloud-bootstrap] %s' "${STATUS[*]:-done}"
  if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
    printf ' | warnings: %s' "$(IFS=';'; printf '%s' "${WARNINGS[*]}")"
  fi
  printf ' | log: %s\n' "${LOG_FILE}"
fi
exit 0
