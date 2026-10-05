#!/usr/bin/env pwsh
# plugins.json にあって未導入の Codex plugin を追加する。未宣言 plugin は削除しない（apply.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

Write-Host '==> Adding missing plugins from plugins.json...'
& pwsh -NoLogo -NoProfile -File (Join-Path $DotfilesDir 'ai\codex\plugin\diff.ps1') -Action apply
exit $LASTEXITCODE
