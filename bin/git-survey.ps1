#!/usr/bin/env pwsh
# git-survey: main 以外のブランチを表示（ローカル + リモート）
#
# 使い方:
#   git-survey [main-branch]
#
# デフォルトの main ブランチ名: main

Set-StrictMode -Version Latest

$MAIN = if ($args.Count -gt 0) { $args[0] } else { 'main' }

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    exit 0
}

& git fetch --all --prune --quiet *> $null

$locals = @(& git branch --format='%(refname:short)') | Where-Object { $_ -ne $MAIN }
$remotes = @(& git branch -r) |
    Where-Object { $_ -notmatch ' -> ' -and $_ -notmatch "/$([regex]::Escape($MAIN))$" } |
    ForEach-Object { ($_ -replace '^\s+', '') -replace '^[^/]+/', '' } |
    Sort-Object -Unique

$all = @($locals + $remotes) | Where-Object { $_ -ne '' } | Sort-Object -Unique

if (-not $all) {
    exit 0
}

Write-Host "Branches (non-${MAIN}):"
foreach ($b in $all) {
    $inLocal = $locals -contains $b
    $inRemote = $remotes -contains $b
    if ($inLocal -and $inRemote) {
        Write-Host "  $b"
    } elseif ($inLocal) {
        Write-Host "  $b  (local)"
    } else {
        Write-Host "  $b  (remote)"
    }
}
