#!/usr/bin/env pwsh
# ai/claude/settings.json用のgit clean filter（jsonsort、git/gitconfig参照）が
# 使用するjqを導入する。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get-Command はプロセスのPATH環境変数に依存し、winget install直後（PATH未反映）を
# 誤って「未インストール」判定してしまうため、winget自身の管理台帳で確認する。
& winget list --id jqlang.jq --exact --accept-source-agreements *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host '  SKIP    jq (already installed)'
    exit 0
}

& winget install --id jqlang.jq --exact --silent --accept-source-agreements --accept-package-agreements
if ($LASTEXITCODE -ne 0) {
    throw "winget install jqlang.jq failed with exit code $LASTEXITCODE"
}
Write-Host '  INSTALL jq'
