#!/usr/bin/env bash
set -euo pipefail

# bin/unix/obsidian-project-home の回帰テスト。使い捨てのGit repositoryと
# Vaultをテンポラリディレクトリへ作るため、ネットワーク・実Vault・private設定へ影響しない。

COMMAND="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/unix/obsidian-project-home"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/obsidian-project-home-test.XXXXXX")"
WORK="$(cd "${WORK}" && pwd)"
VAULT="${WORK}/vault"
REPOSITORY="${WORK}/repository"
FAILURES=0

cleanup() {
  rm -rf "${WORK}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

expect_status() {
  local expected="$1"
  shift
  local status
  set +e
  "$@" >/dev/null 2>&1
  status=$?
  set -e
  [[ "${status}" -eq "${expected}" ]] || fail "expected exit ${expected}, got ${status}: $*"
}

write_project() {
  local name="$1" repository_url="$2"
  mkdir -p "${VAULT}/projects"
  {
    printf '%s\n' '---'
    printf '%s\n' 'type: project'
    printf '%s\n' 'repositories:'
    printf '%s\n' "  - \"${repository_url}\""
    printf '%s\n' '---'
    printf '%s\n' "# ${name}"
  } > "${VAULT}/projects/${name}.md"
}

git init -q "${REPOSITORY}"

write_project unique 'https://github.com/Y-Marui/Example.git'
git -C "${REPOSITORY}" remote add origin 'git@github.com:y-marui/example.git'
result="$("${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}")"
[[ "${result}" == "${VAULT}/projects/unique.md" ]] || fail 'SSH origin did not resolve the normalized Project Home'

git -C "${REPOSITORY}" remote set-url origin 'github-public:y-marui/example.git'
result="$("${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}")"
[[ "${result}" == "${VAULT}/projects/unique.md" ]] || fail 'github-public origin did not resolve the normalized Project Home'

git -C "${REPOSITORY}" remote set-url origin 'https://github.com/y-marui/not-mapped.git'
expect_status 3 "${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}"

write_project duplicate 'https://github.com/y-marui/example'
git -C "${REPOSITORY}" remote set-url origin 'https://github.com/y-marui/example.git'
expect_status 4 "${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}"
expect_status 4 "${COMMAND}" check --vault "${VAULT}"

rm -f "${VAULT}/projects/duplicate.md"
printf '%s\n' '---' 'repositories: https://github.com/y-marui/invalid' '---' > "${VAULT}/projects/invalid.md"
expect_status 5 "${COMMAND}" check --vault "${VAULT}"

# Windowsのautocrlfで取得したVaultのノートはCRLFになる。行末の復帰文字で前文の判定が外れて
# 「対応なし」(3)に見えないよう、CRLFのノートも同じ結果で解決する。
printf '%s\r\n' '---' 'type: project' 'repositories:' '  - "https://github.com/y-marui/crlf-example"' '---' > "${VAULT}/projects/crlf.md"
rm -f "${VAULT}/projects/invalid.md"
git -C "${REPOSITORY}" remote set-url origin 'https://github.com/y-marui/crlf-example.git'
result="$("${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}")"
[[ "${result}" == "${VAULT}/projects/crlf.md" ]] || fail 'CRLF Project Home did not resolve'
rm -f "${VAULT}/projects/crlf.md"

# ディレクトリのシンボリックリンク経由（~/.local/bin/dotfiles 相当）で呼んでも、
# 設定ファイルの場所をリンク位置から誤って導出しない。
mkdir -p "${WORK}/a"
ln -s "$(dirname "${COMMAND}")" "${WORK}/a/link"
set +e
LINK_OUTPUT="$(env -u OBSIDIAN_VAULT_ROOT "${WORK}/a/link/obsidian-project-home" --repo "${REPOSITORY}" 2>&1)"
set -e
[[ "${LINK_OUTPUT}" != *"${WORK}-private"* ]] || fail "resolver config path derived from symlink location: ${LINK_OUTPUT}"

# --- ensure: 許可オーナーのProject Homeだけを作る ---
# 実機のprivate設定(auto_create_owners)を読まないよう、設定の置き場所が存在しない
# 一時ディレクトリへコピーしたコマンドでテストする。
mkdir -p "${WORK}/dot/bin/unix"
command cp -f "${COMMAND}" "${WORK}/dot/bin/unix/obsidian-project-home"
COMMAND="${WORK}/dot/bin/unix/obsidian-project-home"
ENSURE_ERR="${WORK}/ensure-stderr"

reset_ensure() {
  rm -rf "${VAULT}" "${REPOSITORY}"
  mkdir -p "${VAULT}/projects"
  git init -q "${REPOSITORY}"
  git -C "${REPOSITORY}" remote add origin "$1"
  unset OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS
}

ensure_run() { # ensure_run <expected-status> [ensure args...]; stdoutはENSURE_OUT、stderrはENSURE_ERRへ
  local expected="$1" status
  shift
  set +e
  ENSURE_OUT="$("${COMMAND}" ensure --repo "${REPOSITORY}" --vault "${VAULT}" "$@" 2>"${ENSURE_ERR}")"
  status=$?
  set -e
  [[ "${status}" -eq "${expected}" ]] || fail "ensure expected exit ${expected}, got ${status}: $*"
}

count_notes() { find "${VAULT}" -name '*.md' | wc -l | tr -d ' '; }

# 許可オーナーがなければresolveと同じ(3)で、何も作らない。
reset_ensure 'github-public:y-marui/new-repo.git'
ensure_run 3
[[ "$(count_notes)" == 0 ]] || fail 'ensure created a note although no owner is allowed'
grep -q 'automatic creation is not enabled' "${ENSURE_ERR}" || fail 'ensure did not explain the refusal'

# 許可オーナー(大文字小文字・空白は無視)ではProject Homeを作り、自分自身に解決される。
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='someone-else, Y-Marui'
ensure_run 0
CREATED="${VAULT}/projects/repositories/new-repo.md"
[[ "${ENSURE_OUT}" == "${CREATED}" ]] || fail "ensure returned the wrong path: ${ENSURE_OUT}"
[[ "$(cat "${ENSURE_ERR}")" == "created: ${CREATED}" ]] || fail 'ensure did not report the creation on stderr'
result="$("${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}")"
[[ "${result}" == "${CREATED}" ]] || fail 'the created note does not resolve'
expect_status 0 "${COMMAND}" check --vault "${VAULT}"
grep -q '^type: project$' "${CREATED}" || fail 'created note has no type'
grep -q '^status: active$' "${CREATED}" || fail 'created note has no status'
grep -qF '  - "https://github.com/y-marui/new-repo"' "${CREATED}" || fail 'created note has the wrong repositories entry'
for heading in Outcome 'Current state' 'Next actions' Decisions 'Open questions' 'Key context' 'External systems' Changelog; do
  grep -q "^## ${heading}\$" "${CREATED}" || fail "created note lacks the heading: ${heading}"
done

# 2回目は何も作らず、同じパスを返し、ファイルも変えない。
BEFORE="$(shasum "${CREATED}")"
ensure_run 0
[[ "${ENSURE_OUT}" == "${CREATED}" && ! -s "${ENSURE_ERR}" ]] || fail 'second ensure was not a quiet no-op'
[[ "$(shasum "${CREATED}")" == "${BEFORE}" ]] || fail 'second ensure changed the note'

# 別リポジトリのノートと名前が衝突したら、オーナー付きの名前にして既存を壊さない。
reset_ensure 'https://github.com/y-marui/taken.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
mkdir -p "${VAULT}/projects/repositories"
printf '%s\n' '---' 'type: project' 'repositories:' '  - "https://github.com/other/taken"' '---' '# other' > "${VAULT}/projects/repositories/taken.md"
ensure_run 0
[[ "${ENSURE_OUT}" == "${VAULT}/projects/repositories/y-marui-taken.md" ]] || fail "name collision not handled: ${ENSURE_OUT}"
grep -q 'other/taken' "${VAULT}/projects/repositories/taken.md" || fail 'ensure overwrote an existing note'

# 重複(4)・不正なノート(5)・未対応/欠落したorigin(5)では何も作らない。
reset_ensure 'https://github.com/y-marui/dup.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
write_project dup-a 'https://github.com/y-marui/dup'
write_project dup-b 'https://github.com/y-marui/dup'
ensure_run 4
[[ ! -e "${VAULT}/projects/repositories" ]] || fail 'ensure created a note despite duplicates'
reset_ensure 'https://github.com/y-marui/bad.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
printf '%s\n' '---' 'repositories: not-a-list' '---' > "${VAULT}/projects/broken.md"
ensure_run 5
[[ ! -e "${VAULT}/projects/repositories" ]] || fail 'ensure created a note despite an invalid note'
reset_ensure 'https://gitlab.com/y-marui/x.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
ensure_run 5
git -C "${REPOSITORY}" remote remove origin
ensure_run 5

# --descriptionは1行のYAML文字列として安全に書かれ、複数行は拒否して何も残さない。
reset_ensure 'https://github.com/y-marui/described.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
ensure_run 0 --description 'He said "hi" \ done'
grep -qF 'description: "He said \"hi\" \\ done"' "${ENSURE_OUT}" || fail 'description was not escaped'
result="$("${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}")"
[[ "${result}" == "${VAULT}/projects/repositories/described.md" ]] || fail 'a note with a quoted description does not resolve'
reset_ensure 'https://github.com/y-marui/multi.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
ensure_run 1 --description $'two\nlines'
[[ "$(count_notes)" == 0 ]] || fail 'ensure left a note after rejecting the description'

# 許可オーナーはresolver configの auto_create_owners からも読まれる。
reset_ensure 'https://github.com/y-marui/fromconfig.git'
mkdir -p "${WORK}/dot-private/obsidian"
printf 'vault_root=%s\n  auto_create_owners = y-marui\n' "${VAULT}" > "${WORK}/dot-private/obsidian/project-home-resolver.conf"
result="$(env -u OBSIDIAN_VAULT_ROOT "${COMMAND}" ensure --repo "${REPOSITORY}" 2>/dev/null)"
[[ "${result}" == "${VAULT}/projects/repositories/fromconfig.md" ]] || fail "owners from the config were not honored: ${result}"
result="$(env -u OBSIDIAN_VAULT_ROOT "${COMMAND}" --repo "${REPOSITORY}")"
[[ "${result}" == "${VAULT}/projects/repositories/fromconfig.md" ]] || fail 'resolve fails with the extended config'

# 既定のresolveは、許可オーナーでも何も作らない。
reset_ensure 'https://github.com/y-marui/readonly.git'
export OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS='y-marui'
expect_status 3 "${COMMAND}" --repo "${REPOSITORY}" --vault "${VAULT}"
[[ "$(count_notes)" == 0 ]] || fail 'resolve created a note'
unset OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS

if [[ "${FAILURES}" -eq 0 ]]; then
  printf 'All obsidian-project-home regression checks passed.\n'
else
  printf '%s obsidian-project-home regression check(s) failed.\n' "${FAILURES}" >&2
  exit 1
fi
