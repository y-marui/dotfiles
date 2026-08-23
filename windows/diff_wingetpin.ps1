#!/usr/bin/env pwsh
# WingetPin（宣言）とWingetPin.cache（実際のpin状態）を比較する。

param(
    [switch]$Summary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pinFile = Join-Path $PSScriptRoot 'WingetPin'
$cacheFile = Join-Path $PSScriptRoot 'WingetPin.cache'

if (-not (Test-Path -LiteralPath $cacheFile)) {
    exit 1
}

function Get-DeclaredIds {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
            Where-Object { $_ -ne '' }
    ) | Sort-Object -Unique
}

$declared = @(Get-DeclaredIds $pinFile)
$actual = @(Get-DeclaredIds $cacheFile)

$onlyActual = @($actual | Where-Object { $declared -notcontains $_ })
$onlyDeclared = @($declared | Where-Object { $actual -notcontains $_ })

if ($Summary) {
    $parts = @()
    if ($onlyActual.Count -gt 0) { $parts += "+$($onlyActual.Count) cache のみ" }
    if ($onlyDeclared.Count -gt 0) { $parts += "-$($onlyDeclared.Count) files のみ" }
    if ($parts.Count -gt 0) {
        Write-Host ($parts -join ' / ')
        exit 1
    }
    exit 0
}

if ($onlyActual.Count -eq 0 -and $onlyDeclared.Count -eq 0) {
    Write-Host 'No diff: WingetPin.cache と WingetPin は一致しています。'
    exit 0
}

if ($onlyActual.Count -gt 0) {
    Write-Host 'pin済みだがWingetPin未記載 (+cache のみ):'
    foreach ($id in $onlyActual) { Write-Host "  [+cache]  $id" }
    Write-Host ''
}
if ($onlyDeclared.Count -gt 0) {
    Write-Host 'WingetPinにあるが未pin (-files のみ):'
    foreach ($id in $onlyDeclared) { Write-Host "  [-files]  $id" }
}

exit 1
