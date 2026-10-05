#!/usr/bin/env pwsh
# plugins.json 未記載の Codex plugin を削除する（prune.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

& pwsh -NoLogo -NoProfile -File (Join-Path $DotfilesDir 'ai\codex\plugin\diff.ps1') -Action prune
exit $LASTEXITCODE
