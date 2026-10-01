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

if [[ "${FAILURES}" -eq 0 ]]; then
  printf 'All obsidian-project-home regression checks passed.\n'
else
  printf '%s obsidian-project-home regression check(s) failed.\n' "${FAILURES}" >&2
  exit 1
fi
