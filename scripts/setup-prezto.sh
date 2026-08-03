#!/usr/bin/env bash
set -euo pipefail

prezto_root="${ZDOTDIR:-$HOME}"
prezto_dir="${prezto_root}/.zprezto"

if [[ -d "${prezto_dir}/.git" ]]; then
  git -C "${prezto_dir}" submodule sync --recursive
  git -C "${prezto_dir}" submodule update --init --recursive
  echo "  READY   zprezto (${prezto_dir})"
  exit 0
fi

if [[ -e "${prezto_dir}" ]]; then
  echo "error: ${prezto_dir} exists but is not a Git repository" >&2
  exit 1
fi

git clone --recursive https://github.com/sorin-ionescu/prezto.git "${prezto_dir}"
echo "  INSTALL zprezto (${prezto_dir})"
