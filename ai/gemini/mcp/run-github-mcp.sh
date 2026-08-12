#!/usr/bin/env bash
# run-github-mcp.sh
# gh auth token または環境変数 GITHUB_PERSONAL_ACCESS_TOKEN からトークンを取得し、
# GitHub MCP サーバー (docker) を起動するラッパースクリプト。

set -euo pipefail

if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
  IFS= read -r GITHUB_PERSONAL_ACCESS_TOKEN < <(gh auth token 2>/dev/null || true)
fi

if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
  echo "Error: GitHub CLI (gh) is not logged in and GITHUB_PERSONAL_ACCESS_TOKEN is not set." >&2
  echo "Please run 'gh auth login' or set GITHUB_PERSONAL_ACCESS_TOKEN." >&2
  exit 1
fi

export GITHUB_PERSONAL_ACCESS_TOKEN
exec docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server "$@"
