#!/usr/bin/env pwsh
# WingetPinの宣言に実際のwinget pin状態を一致させる。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pinFile = Join-Path $PSScriptRoot 'WingetPin'
$cacheFile = Join-Path $PSScriptRoot 'WingetPin.cache'

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

foreach ($id in $declared) {
    if ($actual -notcontains $id) {
        Write-Host "  pin    $id"
        & winget pin add --id $id --exact
        if ($LASTEXITCODE -ne 0) { throw "winget pin add failed for $id" }
    }
}

foreach ($id in $actual) {
    if ($declared -notcontains $id) {
        Write-Host "  unpin  $id"
        & winget pin remove --id $id --exact
        if ($LASTEXITCODE -ne 0) { throw "winget pin remove failed for $id" }
    }
}

& pwsh -NoLogo -NoProfile -File (Join-Path $PSScriptRoot 'update_wingetpin_cache.ps1')
if ($LASTEXITCODE -ne 0) { throw "update_wingetpin_cache.ps1 failed with exit code $LASTEXITCODE" }
