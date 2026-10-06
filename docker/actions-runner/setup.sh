#!/usr/bin/env bash
# private リポジトリ向けの Linux self-hosted runner（Docker コンテナ）を作る・消す。
# リポジトリごとに 1 コンテナ（個人アカウントにはアカウント単位の runner がないため）。
#
# 使い方（docker と、リポジトリの管理者権限で認証済みの gh が要る）:
#   bash docker/actions-runner/setup.sh build
#   bash docker/actions-runner/setup.sh install [--dry-run] OWNER/REPO...
#   bash docker/actions-runner/setup.sh status  OWNER/REPO...
#   bash docker/actions-runner/setup.sh uninstall [--dry-run] OWNER/REPO...
#
# 環境変数:
#   RUNNER_LABEL   runner に付けるラベル（既定: linux-sh）
#   RUNNER_HOST    runner 名の接頭辞（既定: hostname -s）
#   RUNNER_IMAGE   イメージ名（既定: y-marui/actions-runner:linux）
#   RUNNER_CPUS / RUNNER_MEMORY   コンテナごとの上限（任意。例: 2 / 4g）
#
# 方針と条件は dev-charter の topics/CI_POLICY-full.md「Runner Billing」を参照する。
# リポジトリ名はこのファイルに持たせない（引数で渡す）。登録トークンはファイルに残さない。
# runner の登録状態は、リポジトリごとの Docker volume（ar-<repo>）に保存する。

set -euo pipefail

RUNNER_LABEL="${RUNNER_LABEL:-linux-sh}"
RUNNER_HOST="${RUNNER_HOST:-$(hostname -s)}"
RUNNER_IMAGE="${RUNNER_IMAGE:-y-marui/actions-runner:linux}"
CACHE_VOLUME="ar-cache"
DRY_RUN=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    printf '  + %s\n' "$*"
    return 0
  fi
  "$@"
}

container_name() {
  printf 'ar-%s' "${1#*/}"
}

container_exists() {
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

require_private() {
  local repo="$1" private
  private="$(gh api "repos/${repo}" --jq .private)" || die "${repo} を取得できません"
  [[ "${private}" == "true" ]] || die "${repo} は public です。public には runner を登録しません（fork の PR が任意のコードを実行できるため）"
}

cmd_build() {
  run docker build -t "${RUNNER_IMAGE}" "${SCRIPT_DIR}"
}

cmd_install() {
  local repo name cname reg args
  for repo in "$@"; do
    echo "== ${repo}"
    [[ "${repo}" == */* ]] || die "OWNER/REPO の形式で指定してください: ${repo}"
    require_private "${repo}"
    cname="$(container_name "${repo}")"
    name="${RUNNER_HOST}-${repo#*/}"

    if container_exists "${cname}"; then
      log "コンテナ ${cname} は既にあります（スキップ。作り直すには uninstall してから）"
      continue
    fi

    args=(docker run -d --name "${cname}" --restart unless-stopped
      -e "REPO_URL=https://github.com/${repo}"
      -e "RUNNER_NAME=${name}"
      -e "RUNNER_LABELS=${RUNNER_LABEL}"
      -v "${cname}:/runner/actions-runner"
      -v "${CACHE_VOLUME}:/runner/.cache")
    [[ -n "${RUNNER_CPUS:-}" ]] && args+=(--cpus "${RUNNER_CPUS}")
    [[ -n "${RUNNER_MEMORY:-}" ]] && args+=(--memory "${RUNNER_MEMORY}")

    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "+ gh api -X POST repos/${repo}/actions/runners/registration-token"
      log "+ ${args[*]} -e REG_TOKEN=<token> ${RUNNER_IMAGE}"
      continue
    fi
    reg="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
    "${args[@]}" -e "REG_TOKEN=${reg}" "${RUNNER_IMAGE}" >/dev/null
    log "登録しました: ${name}（label ${RUNNER_LABEL}）"
  done
}

cmd_status() {
  local repo
  for repo in "$@"; do
    echo "== ${repo}"
    docker ps -a --filter "name=^$(container_name "${repo}")$" --format '  container: {{.Names}} {{.Status}}'
    gh api "repos/${repo}/actions/runners" \
      --jq '.runners[] | "  github: \(.name) \(.status) busy=\(.busy) [\([.labels[].name]|join(","))]"'
  done
}

cmd_uninstall() {
  local repo cname rm
  for repo in "$@"; do
    echo "== ${repo}"
    cname="$(container_name "${repo}")"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "+ gh api -X POST repos/${repo}/actions/runners/remove-token"
      log "+ docker exec ${cname} ./config.sh remove --token <token>"
      log "+ docker rm -f ${cname}; docker volume rm ${cname}"
      continue
    fi
    if container_exists "${cname}"; then
      rm="$(gh api -X POST "repos/${repo}/actions/runners/remove-token" --jq .token)"
      docker exec "${cname}" ./config.sh remove --token "${rm}" || log "GitHub 側の解除に失敗しました（手動で削除してください）"
      docker rm -f "${cname}" >/dev/null
      docker volume rm "${cname}" >/dev/null
      log "削除しました: ${cname}"
    else
      log "コンテナ ${cname} はありません"
    fi
  done
}

main() {
  local sub="${1:-}"
  [[ -n "${sub}" ]] || die "usage: $0 build|install|status|uninstall [--dry-run] OWNER/REPO..."
  shift
  if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
  fi
  case "${sub}" in
    build) cmd_build ;;
    install | status | uninstall)
      [[ $# -gt 0 ]] || die "OWNER/REPO を 1 つ以上指定してください"
      "cmd_${sub}" "$@"
      ;;
    *) die "unknown subcommand: ${sub}" ;;
  esac
}

main "$@"
