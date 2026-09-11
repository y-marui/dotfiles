# shellcheck shell=bash
# bin/unix/_ghq-lib.sh
# ghq-pull / ghq-update / ghq-sweep から source される共通関数。
#
# uv.lock・package-lock.json はローカルの `uv sync`/`npm update` 等で
# 頻繁に更新され、コミットされていない差分を抱えやすい。これだけを理由に
# dirty working tree として処理全体をスキップしてしまうと ghq-pull /
# ghq-update / ghq-sweep が実質的に動かなくなるため、これらロックファイル
# のみが dirty な場合は一時的に stash して処理を継続し、処理後に復元する。
# ロックファイル以外にも dirty な変更がある場合は従来通りスキップする。

_GHQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GHQ_UPSTREAM_PR_ALLOW_FILE="${_GHQ_LIB_DIR}/../ghq-upstream-pr-allow"

_GHQ_PRIORITY_REPOS=(dotfiles dev-charter)

# _ghq_ordered_list <filter>
# ghq list -p の結果を、_GHQ_PRIORITY_REPOS に列挙したリポジトリ（存在し filter に
# 一致するもののみ）を先頭に、残りを sort -fV した順で出力する。
# dotfiles はツール自体（ghq-update 等のスクリプト）を、dev-charter は各リポジトリの
# 基準バージョン（docs/dev-charter/VERSION の比較元）を提供するため、他のリポジトリ
# より先に最新化しておきたい。
_ghq_ordered_list() {
  local filter="$1" all rest name repo

  all="$(ghq list -p | grep -iE -- "$filter")" || true
  if [[ -z "${all}" ]]; then
    return 0
  fi

  rest="${all}"
  for name in "${_GHQ_PRIORITY_REPOS[@]}"; do
    repo="$(printf '%s\n' "${rest}" | grep -iE "/${name}\$" | head -1)" || true
    if [[ -z "${repo}" ]]; then
      continue
    fi
    printf '%s\n' "${repo}"
    rest="$(printf '%s\n' "${rest}" | grep -ivFx "${repo}")" || true
  done

  if [[ -n "${rest}" ]]; then
    printf '%s\n' "${rest}" | sort -fV
  fi

  return 0
}

_GHQ_STASHED=false
_GHQ_LOCKFILES=(uv.lock package-lock.json)

# _ghq_stash_lockfiles <repo>
# 戻り値 0: 処理続行可（clean、または _GHQ_LOCKFILES のみ dirty で stash 済み）
# 戻り値 1: _GHQ_LOCKFILES 以外にも dirty な変更があるためスキップすべき
_ghq_stash_lockfiles() {
  local repo="$1" porcelain other f dirty=()

  _GHQ_STASHED=false
  porcelain="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
  [[ -z "${porcelain}" ]] && return 0

  other="${porcelain}"
  for f in "${_GHQ_LOCKFILES[@]}"; do
    other="$(printf '%s\n' "${other}" | grep -v -E " ${f//./\\.}\$" || true)"
  done
  [[ -n "${other}" ]] && return 1

  for f in "${_GHQ_LOCKFILES[@]}"; do
    printf '%s\n' "${porcelain}" | grep -q -E " ${f//./\\.}\$" && dirty+=("$f")
  done
  [[ ${#dirty[@]} -eq 0 ]] && return 0

  git -C "$repo" stash push --include-untracked --quiet \
    --message "ghq-lib: lockfiles" -- "${dirty[@]}" || return 1
  _GHQ_STASHED=true
  return 0
}

# _ghq_unstash_lockfiles <repo>
# _ghq_stash_lockfiles で stash したロックファイルを復元する。
# pull 等でリモート側も同じファイルを更新していた場合はコンフリクトしうるため、
# その場合は stash を残したまま失敗を報告する（自動では解決しない）。
_ghq_unstash_lockfiles() {
  local repo="$1"

  [[ "${_GHQ_STASHED}" == true ]] || return 0

  if git -C "$repo" stash pop --quiet; then
    return 0
  fi
  echo "  [conflict] ロックファイルの復元に失敗（手動で解決してください: cd ${repo} && git stash list）" >&2
  return 1
}

_GHQ_UV_LOCK_PR_BRANCH='chore/uv-lock-update'
_GHQ_NPM_LOCK_PR_BRANCH='chore/npm-lock-update'

# _ghq_remote_owner_repo <repo> <remote>
# <remote> の URL から owner/repo を切り出す。`gh repo view <url>` による解決は
# ~/.ssh/config の Host エイリアス（例: github-public:owner/repo.git）を解釈できない
# ため使わず、正規表現で抜き出す。
_ghq_remote_owner_repo() {
  local repo="$1" remote="$2"
  git -C "$repo" remote get-url "$remote" 2>/dev/null \
    | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#'
}

# _ghq_upstream_pr_allowed <owner/repo>
# bin/ghq-upstream-pr-allow に列挙された owner/repo パターン（glob可、# 以降はコメント）の
# いずれかに一致すれば 0 を返す。ファイルが無い・一致しなければ 1 を返す。
_ghq_upstream_pr_allowed() {
  local target="$1" line
  [[ -f "${_GHQ_UPSTREAM_PR_ALLOW_FILE}" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    # shellcheck disable=SC2053
    [[ "$target" == $line ]] && return 0
  done < "${_GHQ_UPSTREAM_PR_ALLOW_FILE}"
  return 1
}

# _ghq_sync_upstream_fork <repo>
# upstream という名前の remote があるリポジトリ（GitHub標準のfork運用）に限り、
# `gh repo sync` で upstream のデフォルトブランチを origin（自分のfork）へ
# fast-forward反映する（diverge していれば警告のみで自動マージはしない）。
# ローカルへの反映は、この関数の呼び出し元が続けて行う origin の
# fetch/pull に任せる。upstream remote が無いリポジトリには何もしない。
# 失敗時も常に 0 を返す。
_ghq_sync_upstream_fork() {
  local repo="$1" origin_repo upstream_repo output

  upstream_repo="$(_ghq_remote_owner_repo "$repo" upstream)"
  [[ -n "${upstream_repo}" ]] || return 0

  if ! command -v gh >/dev/null 2>&1; then
    echo "  [skip upstream-sync] (${repo}) 'gh' が見つかりません" >&2
    return 0
  fi
  if ! (cd "$repo" && gh auth status) >/dev/null 2>&1; then
    echo "  [skip upstream-sync] (${repo}) gh が未認証です" >&2
    return 0
  fi

  origin_repo="$(_ghq_remote_owner_repo "$repo" origin)"
  if [[ -z "${origin_repo}" ]]; then
    echo "  [skip upstream-sync] (${repo}) origin リポジトリを解決できませんでした" >&2
    return 0
  fi

  # 引数無しの `gh repo sync` はローカルの origin remote URL を gh 自身が解決する
  # ため、~/.ssh/config の Host エイリアス（例: github-public:owner/repo.git）を
  # 解釈できず失敗する。正規表現で抜き出し済みの owner/repo を明示的に渡す。
  if output="$(cd "$repo" && gh repo sync "$origin_repo" --source "$upstream_repo" 2>&1)"; then
    echo "  [upstream-sync] upstream と同期しました: ${repo}"
  else
    echo "  [warn][upstream-sync] (${repo}) 同期に失敗しました（fast-forward不可の可能性があります。手動で確認してください）: $(printf '%s' "${output}" | tr '\n' ' ' | cut -c1-500)" >&2
  fi
  return 0
}

# _ghq_auto_pr_lockfile <repo> <base_branch> <lockfile> <branch> <title> <body>
# uv sync --upgrade / npm update により <lockfile> のみが dirty な場合、
# <branch> にコミットして force push し、gh で PR を作成する（既に open な
# PR があれば push だけでその PR に反映される）。作業ツリーは base_branch
# に戻した状態で返す。失敗時も呼び出し元の処理は継続できるよう常に 0 を返す。
_ghq_auto_pr_lockfile() {
  local repo="$1" base_branch="$2" lockfile="$3" branch="$4" title="$5" body="$6" \
    other pr_count origin_repo upstream_repo target_repo head_ref pr_output commit_err

  [[ -z "$(git -C "$repo" status --porcelain -- "$lockfile" 2>/dev/null || true)" ]] && return 0

  other="$(git -C "$repo" status --porcelain 2>/dev/null | grep -v -E " ${lockfile//./\\.}\$" || true)"
  [[ -n "${other}" ]] && { echo "  [skip auto-pr] (${repo}) ${lockfile} 以外にも dirty な変更があります" >&2; return 0; }

  if ! command -v gh >/dev/null 2>&1; then
    echo "  [skip auto-pr] (${repo}) 'gh' が見つかりません（${lockfile} の変更はローカルに残しています）" >&2
    return 0
  fi
  if ! (cd "$repo" && gh auth status) >/dev/null 2>&1; then
    echo "  [skip auto-pr] (${repo}) gh が未認証です（${lockfile} の変更はローカルに残しています）" >&2
    return 0
  fi

  # origin の remote URL から owner/repo を直接切り出す。upstream 等の追加
  # remote がある fork で --repo を渡さずに `gh pr list`/`gh pr create` を
  # 実行すると、gh がベースリポジトリを fork 元（upstream）だと誤解決し、
  # origin にしか存在しないブランチが見つからず PR 作成が常に失敗する
  # （ブランチだけ push されて PR が出ない）ため、明示的に origin を指定する。
  origin_repo="$(_ghq_remote_owner_repo "$repo" origin)"
  if [[ -z "${origin_repo}" ]]; then
    echo "  [skip auto-pr] (${repo}) origin リポジトリを解決できませんでした" >&2
    return 0
  fi

  # upstream remote があり、かつ bin/ghq-upstream-pr-allow で許可されている場合のみ、
  # origin ではなく upstream（fork元）へ PR を作成する。head は fork からの
  # クロスリポジトリPRとして "<originのowner>:<branch>" 形式で指定する。
  target_repo="$origin_repo"
  head_ref="$branch"
  upstream_repo="$(_ghq_remote_owner_repo "$repo" upstream)"
  if [[ -n "${upstream_repo}" ]] && _ghq_upstream_pr_allowed "${upstream_repo}"; then
    target_repo="${upstream_repo}"
    head_ref="${origin_repo%%/*}:${branch}"
  fi

  if ! git -C "$repo" checkout -B "$branch" >/dev/null 2>&1; then
    echo "  [skip auto-pr] (${repo}) ブランチ作成に失敗しました" >&2
    return 0
  fi
  if ! commit_err="$(git -C "$repo" commit -m "$title" -- "$lockfile" 2>&1)"; then
    echo "  [skip auto-pr] (${repo}) commit に失敗しました: $(printf '%s' "${commit_err}" | tr '\n' ' ' | cut -c1-500)" >&2
    git -C "$repo" checkout "$base_branch" >/dev/null 2>&1 || true
    return 0
  fi
  if ! git -C "$repo" push --force-with-lease -u origin "$branch" >/dev/null 2>&1; then
    echo "  [warn] push に失敗しました（ローカルブランチ '${branch}' に残しています: ${repo}）" >&2
    git -C "$repo" checkout "$base_branch" >/dev/null 2>&1 || true
    return 0
  fi

  if [[ "$target_repo" == "$origin_repo" ]]; then
    pr_count="$(cd "$repo" && gh pr list --repo "$target_repo" --head "$head_ref" --state open --json number -q 'length' 2>/dev/null || echo 0)"
  else
    # `gh pr list --head` は "<owner>:<branch>" 形式に非対応（gh pr list --help に明記）
    # なため、target_repo 全体を取得して headRepositoryOwner/headRefName でフィルタする。
    pr_count="$(cd "$repo" && gh pr list --repo "$target_repo" --state open \
      --json number,headRefName,headRepositoryOwner \
      -q "[.[] | select(.headRefName == \"${branch}\" and .headRepositoryOwner.login == \"${origin_repo%%/*}\")] | length" \
      2>/dev/null || echo 0)"
  fi
  if [[ "${pr_count}" == "0" ]]; then
    local pr_create_args=(--repo "$target_repo" --title "$title" \
      --body "$body" \
      --base "$base_branch" --head "$head_ref")
    # 自分（y-marui）名義のリポジトリでは見逃し防止のため自分を assignee にする
    [[ "${target_repo}" == y-marui/* ]] && pr_create_args+=(--assignee y-marui)
    if pr_output="$(cd "$repo" && gh pr create "${pr_create_args[@]}" 2>&1)"; then
      # dots update 実行後にまとめて気付けるよう warning 扱いで報告する
      echo "  [warn][auto-pr] PR を作成しました: ${branch} ${pr_output}" >&2
    else
      echo "  [warn] PR 作成に失敗しました（ブランチは push 済み: ${branch}）: ${pr_output}" >&2
    fi
  else
    echo "  [auto-pr] 既存 PR を更新しました: ${branch}"
  fi

  git -C "$repo" checkout "$base_branch" >/dev/null 2>&1 || true
  return 0
}
