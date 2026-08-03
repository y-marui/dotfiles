#!/usr/bin/env bash
set -euo pipefail

prezto_root="${ZDOTDIR:-$HOME}"
prezto_dir="${prezto_root}/.zprezto"

if [[ ! -d "${prezto_dir}/.git" ]]; then
  echo "  SKIP    zprezto (${prezto_dir} is not installed)"
  exit 0
fi

branch="$(git -C "${prezto_dir}" symbolic-ref --quiet --short HEAD || true)"
if [[ "${branch}" != "master" ]]; then
  echo "error: zprezto is on '${branch:-detached HEAD}', expected 'master'" >&2
  exit 1
fi

if [[ -n "$(git -C "${prezto_dir}" status --short)" ]]; then
  echo "error: zprezto has local changes; update skipped" >&2
  exit 1
fi

git -C "${prezto_dir}" pull --ff-only
git -C "${prezto_dir}" submodule sync --recursive
git -C "${prezto_dir}" submodule update --init --recursive
echo "  UPDATE  zprezto (${prezto_dir})"
