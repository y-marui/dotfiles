#!/usr/bin/env bash
# private リポジトリ向けに、macOS のネイティブ GitHub Actions self-hosted runner を
# 専用ユーザー + LaunchDaemon で登録・解除する（ログインセッション不要で常駐する）。
#
# 使い方（通常ユーザーで実行する。内部で必要な箇所だけ sudo を呼ぶ）:
#   bash macos/setup_actions_runner.sh install [--dry-run] OWNER/REPO...
#   bash macos/setup_actions_runner.sh status  OWNER/REPO...
#   bash macos/setup_actions_runner.sh uninstall [--dry-run] OWNER/REPO...
#
# 環境変数:
#   RUNNER_USER     専用ユーザー名（既定: ghrunner。管理者権限のない標準ユーザー）
#   RUNNER_LABEL    runner に付けるラベル（既定: macos-sh）
#   XCODE_APP       CI で使う Xcode（既定: /Applications/Xcode-26.6.app）
#   RUNNER_VERSION  runner のバージョン（既定: 最新リリース）
#
# 方針と条件は dev-charter の topics/CI_POLICY-full.md「Runner Billing」を参照する。
# リポジトリ名はこのファイルに持たせない（引数で渡す）。登録トークンはファイルに残さない。

set -euo pipefail

RUNNER_USER="${RUNNER_USER:-ghrunner}"
RUNNER_LABEL="${RUNNER_LABEL:-macos-sh}"
XCODE_APP="${XCODE_APP:-/Applications/Xcode-26.6.app}"
RUNNER_VERSION="${RUNNER_VERSION:-}"
SVC_PREFIX="com.y-marui.actions-runner"
DRY_RUN=0
RUNNER_HOME=""
TARBALL=""
WORK_TMP=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '  %s\n' "$*"
}

# dry-run では実行せずに表示だけする
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    if [[ "$1" == "as_runner" ]]; then
      printf '  + sudo -u %s -H %s\n' "${RUNNER_USER}" "${*:2}"
    else
      printf '  + %s\n' "$*"
    fi
    return 0
  fi
  "$@"
}

cleanup() {
  if [[ -n "${WORK_TMP}" && -d "${WORK_TMP}" ]]; then
    rm -rf "${WORK_TMP}"
  fi
}
trap cleanup EXIT

# runner ユーザーとして実行する（ホームは runner ユーザーのもの）
as_runner() {
  sudo -u "${RUNNER_USER}" -H "$@"
}

# runner ユーザーのホーム配下は通常ユーザーから読めないため、確認も sudo 経由で行う。
# dry-run では sudo を呼ばず「存在しない」として扱う
runner_has() {
  [[ "${DRY_RUN}" -eq 1 ]] && return 1
  as_runner test -e "$1"
}

preflight() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS 専用です"
  [[ "$(id -u)" -ne 0 ]] || die "sudo を付けずに実行してください（必要な箇所だけ内部で sudo を呼びます）"
  id "${RUNNER_USER}" >/dev/null 2>&1 || die "ユーザー ${RUNNER_USER} がありません"
  if dseditgroup -o checkmember -m "${RUNNER_USER}" admin 2>/dev/null | grep -q '^yes'; then
    die "${RUNNER_USER} が管理者です。管理者権限のない標準ユーザーで実行してください"
  fi
  [[ -x "${XCODE_APP}/Contents/Developer/usr/bin/xcodebuild" ]] ||
    die "Xcode が見つかりません: ${XCODE_APP}"
  command -v gh >/dev/null 2>&1 || die "gh がありません"
  gh auth status >/dev/null 2>&1 || die "gh が未認証です（gh auth login）"
  RUNNER_HOME="$(dscl . -read "/Users/${RUNNER_USER}" NFSHomeDirectory | awk '{print $2}')"
  [[ -n "${RUNNER_HOME}" ]] || die "${RUNNER_USER} のホームを取得できません"
}

# public リポジトリには登録しない（fork の PR が runner 上で任意のコードを実行できるため）
check_repo() {
  local repo="$1" private
  [[ "${repo}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "OWNER/REPO の形式で指定してください: ${repo}"
  private="$(gh api "repos/${repo}" --jq .private)" || die "リポジトリを取得できません: ${repo}"
  [[ "${private}" == "true" ]] || die "${repo} は public です。public には登録しません"
}

download_runner() {
  [[ -n "${TARBALL}" ]] && return 0
  local arch suffix endpoint info name digest url expected actual
  arch="$(uname -m)"
  case "${arch}" in
    arm64) suffix="osx-arm64" ;;
    x86_64) suffix="osx-x64" ;;
    *) die "未対応のアーキテクチャです: ${arch}" ;;
  esac
  if [[ -n "${RUNNER_VERSION}" ]]; then
    endpoint="repos/actions/runner/releases/tags/v${RUNNER_VERSION#v}"
  else
    endpoint="repos/actions/runner/releases/latest"
  fi
  info="$(gh api "${endpoint}" --jq \
    ".assets[] | select(.name | test(\"^actions-runner-${suffix}-[0-9.]+\\\\.tar\\\\.gz\$\")) | [.name, (.digest // \"\"), .browser_download_url] | @tsv")" ||
    die "runner のリリース情報を取得できません"
  [[ -n "${info}" ]] || die "runner のアセットが見つかりません（${suffix}）"
  IFS=$'\t' read -r name digest url <<<"${info}"
  [[ "${digest}" == sha256:* ]] || die "公式のチェックサム（digest）を取得できないため中止します"
  expected="${digest#sha256:}"

  WORK_TMP="$(mktemp -d)"
  TARBALL="${WORK_TMP}/${name}"
  log "download ${name}"
  curl -fsSL -o "${TARBALL}" "${url}"
  actual="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
  [[ "${actual}" == "${expected}" ]] || die "チェックサムが一致しません: ${name}"
  log "sha256 ok"
}

# runner の登録・削除用トークンを標準出力に返す（1 時間で失効する。変数やファイルには保持しない）
runner_token() {
  gh api -X POST "repos/$1/actions/runners/$2-token" --jq .token
}

wait_online() {
  local repo="$1" runner_name="$2" status=""
  for _ in $(seq 1 30); do
    status="$(gh api "repos/${repo}/actions/runners" \
      --jq ".runners[] | select(.name == \"${runner_name}\") | .status" 2>/dev/null || true)"
    [[ "${status}" == "online" ]] && break
    sleep 2
  done
  printf '  RUNNER  %s: %s\n' "${runner_name}" "${status:-not-registered}"
  [[ "${status}" == "online" ]]
}

install_one() {
  local repo="$1" name svc dir plist runner_name runner_path
  name="${repo#*/}"
  svc="${SVC_PREFIX}.${name}"
  dir="${RUNNER_HOME}/actions-runner/${name}"
  plist="/Library/LaunchDaemons/${svc}.plist"
  runner_name="$(scutil --get LocalHostName)-${name}"
  runner_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  printf '== %s\n' "${repo}"
  check_repo "${repo}"
  download_runner

  run as_runner mkdir -p "${dir}"
  if ! runner_has "${dir}/run.sh"; then
    log "extract runner -> ${dir}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      printf '  + sudo -u %s tar -xzf <tarball> -C %s\n' "${RUNNER_USER}" "${dir}"
    else
      as_runner tar -xzf - -C "${dir}" <"${TARBALL}"
    fi
  fi

  if ! runner_has "${dir}/.runner"; then
    log "register runner (${runner_name}, label ${RUNNER_LABEL})"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      printf '  + gh api -X POST repos/%s/actions/runners/registration-token\n' "${repo}"
      printf '  + sudo -u %s ./config.sh --unattended --url https://github.com/%s --token <token> --name %s --labels %s --work _work --replace\n' \
        "${RUNNER_USER}" "${repo}" "${runner_name}" "${RUNNER_LABEL}"
    else
      # トークンは 1 時間で失効する登録専用の値。引数に載るのは config.sh の実行中だけ
      # shellcheck disable=SC2016  # $0/$@ は bash -c 側で展開する
      as_runner bash -c 'cd "$0" && exec ./config.sh "$@"' "${dir}" \
        --unattended --url "https://github.com/${repo}" --token "$(runner_token "${repo}" registration)" \
        --name "${runner_name}" --labels "${RUNNER_LABEL}" --work _work --replace
    fi
  else
    log "already registered (skip config)"
  fi

  # CI が使う Xcode と PATH を固定する（hosted の macos-latest に合わせる）
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '  + write %s/.env (DEVELOPER_DIR=%s)\n  + write %s/.path\n' "${dir}" "${XCODE_APP}/Contents/Developer" "${dir}"
  else
    printf 'DEVELOPER_DIR=%s\n' "${XCODE_APP}/Contents/Developer" | as_runner tee "${dir}/.env" >/dev/null
    printf '%s' "${runner_path}" | as_runner tee "${dir}/.path" >/dev/null
  fi
  run as_runner install -m 755 "${dir}/bin/runsvc.sh" "${dir}/runsvc.sh"
  run as_runner mkdir -p "${RUNNER_HOME}/Library/Logs/${svc}"

  log "install LaunchDaemon ${plist}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '  + generate %s from bin/actions.runner.plist.template (UserName=%s)\n' "${plist}" "${RUNNER_USER}"
    printf '  + sudo launchctl bootstrap system %s\n' "${plist}"
    return 0
  fi
  as_runner cat "${dir}/bin/actions.runner.plist.template" |
    sed "s/{{User}}/${RUNNER_USER}/g; s/{{SvcName}}/${svc}/g; s@{{RunnerRoot}}@${dir}@g; s@{{UserHome}}@${RUNNER_HOME}@g" |
    sudo tee "${plist}" >/dev/null
  sudo chown root:wheel "${plist}"
  sudo chmod 644 "${plist}"
  plutil -lint "${plist}" >/dev/null
  sudo launchctl bootout "system/${svc}" 2>/dev/null || true
  sudo launchctl bootstrap system "${plist}"
  sudo launchctl enable "system/${svc}"
  wait_online "${repo}" "${runner_name}" || log "オンラインを確認できません。ログ: ${RUNNER_HOME}/Library/Logs/${svc}/"
}

uninstall_one() {
  local repo="$1" name svc dir plist
  name="${repo#*/}"
  svc="${SVC_PREFIX}.${name}"
  dir="${RUNNER_HOME}/actions-runner/${name}"
  plist="/Library/LaunchDaemons/${svc}.plist"

  printf '== %s\n' "${repo}"
  run sudo launchctl bootout "system/${svc}" 2>/dev/null || true
  if [[ -f "${plist}" ]]; then
    run sudo rm -f "${plist}"
  fi
  if runner_has "${dir}/.runner" || [[ "${DRY_RUN}" -eq 1 ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      printf '  + gh api -X POST repos/%s/actions/runners/remove-token\n  + sudo -u %s ./config.sh remove --token <token>\n' "${repo}" "${RUNNER_USER}"
    else
      # shellcheck disable=SC2016  # $0/$1 は bash -c 側で展開する
      as_runner bash -c 'cd "$0" && exec ./config.sh remove --token "$1"' "${dir}" "$(runner_token "${repo}" remove)" || true
    fi
  fi
  run as_runner rm -rf "${dir}"
  log "removed ${svc}"
}

status_one() {
  local repo="$1" name svc runner_name
  name="${repo#*/}"
  svc="${SVC_PREFIX}.${name}"
  runner_name="$(scutil --get LocalHostName)-${name}"
  if launchctl print "system/${svc}" >/dev/null 2>&1; then
    printf '  LOADED  %s\n' "${svc}"
  else
    printf '  ABSENT  %s\n' "${svc}"
  fi
  printf '  GITHUB  %s: %s\n' "${runner_name}" \
    "$(gh api "repos/${repo}/actions/runners" --jq ".runners[] | select(.name == \"${runner_name}\") | .status" 2>/dev/null || echo unknown)"
}

main() {
  local action="${1:-}" repos=() arg repo
  [[ -n "${action}" ]] || die "使い方: $0 {install|status|uninstall} [--dry-run] OWNER/REPO..."
  shift
  for arg in "$@"; do
    case "${arg}" in
      --dry-run) DRY_RUN=1 ;;
      *) repos+=("${arg}") ;;
    esac
  done
  [[ "${#repos[@]}" -gt 0 ]] || die "OWNER/REPO を 1 つ以上指定してください"

  preflight
  case "${action}" in
    install)
      for repo in "${repos[@]}"; do install_one "${repo}"; done
      ;;
    uninstall)
      for repo in "${repos[@]}"; do uninstall_one "${repo}"; done
      ;;
    status)
      for repo in "${repos[@]}"; do
        printf '== %s\n' "${repo}"
        status_one "${repo}"
      done
      ;;
    *) die "不明なアクション: ${action}" ;;
  esac
}

main "$@"
