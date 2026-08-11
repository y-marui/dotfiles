# shellcheck shell=bash
# bin/_ghq-lib.sh
# ghq-pull / ghq-update / ghq-sweep から source される共通関数。
#
# uv.lock はローカルの `uv sync` 等で頻繁に更新され、コミットされていない
# 差分を抱えやすい。これだけを理由に dirty working tree として処理全体を
# スキップしてしまうと ghq-pull / ghq-update / ghq-sweep が実質的に動かなく
# なるため、uv.lock のみが dirty な場合は一時的に stash して処理を継続し、
# 処理後に復元する。uv.lock 以外にも dirty な変更がある場合は従来通り
# スキップする。

_GHQ_STASHED=false

# _ghq_stash_uv_lock <repo>
# 戻り値 0: 処理続行可（clean、または uv.lock のみ dirty で stash 済み）
# 戻り値 1: uv.lock 以外にも dirty な変更があるためスキップすべき
_ghq_stash_uv_lock() {
  local repo="$1" porcelain other

  _GHQ_STASHED=false
  porcelain="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
  [[ -z "${porcelain}" ]] && return 0

  other="$(printf '%s\n' "${porcelain}" | grep -v -E ' uv\.lock$' || true)"
  [[ -n "${other}" ]] && return 1

  git -C "$repo" stash push --include-untracked --quiet \
    --message "ghq-lib: uv.lock" -- uv.lock || return 1
  _GHQ_STASHED=true
  return 0
}

# _ghq_unstash_uv_lock <repo>
# _ghq_stash_uv_lock で stash した uv.lock を復元する。
# pull 等でリモート側も uv.lock を更新していた場合はコンフリクトしうるため、
# その場合は stash を残したまま失敗を報告する（自動では解決しない）。
_ghq_unstash_uv_lock() {
  local repo="$1"

  [[ "${_GHQ_STASHED}" == true ]] || return 0

  if git -C "$repo" stash pop --quiet; then
    return 0
  fi
  echo "  [conflict] uv.lock の復元に失敗（手動で解決してください: cd ${repo} && git stash list）" >&2
  return 1
}
