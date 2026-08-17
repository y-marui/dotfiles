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

_GHQ_AUTO_PR_BRANCH='chore/uv-lock-update'

# _ghq_auto_pr_uv_lock <repo> <base_branch>
# uv sync --upgrade により uv.lock のみが dirty な場合、専用ブランチに
# コミットして force push し、gh で PR を作成する（既に open な PR が
# あれば push だけでその PR に反映される）。作業ツリーは base_branch に
# 戻した状態で返す。失敗時も呼び出し元の処理は継続できるよう常に 0 を返す。
_ghq_auto_pr_uv_lock() {
  local repo="$1" base_branch="$2" branch="${_GHQ_AUTO_PR_BRANCH}" other pr_count

  [[ -z "$(git -C "$repo" status --porcelain -- uv.lock 2>/dev/null || true)" ]] && return 0

  other="$(git -C "$repo" status --porcelain 2>/dev/null | grep -v -E ' uv\.lock$' || true)"
  [[ -n "${other}" ]] && { echo "  [skip auto-pr] uv.lock 以外にも dirty な変更があります" >&2; return 0; }

  if ! command -v gh >/dev/null 2>&1; then
    echo "  [skip auto-pr] 'gh' が見つかりません（uv.lock の変更はローカルに残しています）" >&2
    return 0
  fi
  if ! (cd "$repo" && gh auth status) >/dev/null 2>&1; then
    echo "  [skip auto-pr] gh が未認証です（uv.lock の変更はローカルに残しています）" >&2
    return 0
  fi

  if ! git -C "$repo" checkout -B "$branch" >/dev/null 2>&1; then
    echo "  [skip auto-pr] ブランチ作成に失敗しました" >&2
    return 0
  fi
  if ! git -C "$repo" commit -m "chore: update uv.lock" -- uv.lock >/dev/null 2>&1; then
    echo "  [skip auto-pr] commit に失敗しました" >&2
    git -C "$repo" checkout "$base_branch" >/dev/null 2>&1 || true
    return 0
  fi
  if ! git -C "$repo" push --force-with-lease -u origin "$branch" >/dev/null 2>&1; then
    echo "  [warn] push に失敗しました（ローカルブランチ '${branch}' に残しています: ${repo}）" >&2
    git -C "$repo" checkout "$base_branch" >/dev/null 2>&1 || true
    return 0
  fi

  pr_count="$(cd "$repo" && gh pr list --head "$branch" --state open --json number -q 'length' 2>/dev/null || echo 0)"
  if [[ "${pr_count}" == "0" ]]; then
    if (cd "$repo" && gh pr create --title "chore: update uv.lock" \
      --body "uv sync --upgrade により生成された uv.lock の更新です（ghq-update の自動 PR 機能）。" \
      --base "$base_branch" --head "$branch") >/dev/null 2>&1; then
      echo "  [auto-pr] PR を作成しました: ${branch}"
    else
      echo "  [warn] PR 作成に失敗しました（ブランチは push 済み: ${branch}）" >&2
    fi
  else
    echo "  [auto-pr] 既存 PR を更新しました: ${branch}"
  fi

  git -C "$repo" checkout "$base_branch" >/dev/null 2>&1 || true
  return 0
}
