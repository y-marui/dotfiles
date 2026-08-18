#!/usr/bin/env pwsh
# scripts/check.ps1
# Windows 向けシンボリックリンク整合性確認スクリプト。
# macOS/Linux の scripts/check.sh に相当。
#
# 使い方:
#   pwsh scripts/check.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\_links.ps1"

$countOk      = 0
$countBroken  = 0
$countMissing = 0

foreach ($link in $Links) {
    $src  = Join-Path $DOTFILES_DIR $link.Src
    $dest = $link.Dest

    $item = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue -Force
    if ($item -and $item.LinkType -eq 'SymbolicLink') {
        $target = [string]$item.Target
        if (-not [System.IO.Path]::IsPathRooted($target)) {
            $target = Join-Path $item.DirectoryName $target
        }
        if (Test-Path -LiteralPath $target) {
            Write-Host "  OK         $dest"
            $countOk++
        } else {
            Write-Host "  BROKEN     $dest -> $target"
            $countBroken++
        }
    } else {
        Write-Host "  NOT LINKED $dest  (期待: $src)"
        $countMissing++
    }
}

Write-Host ""
Write-Host "OK=$countOk  BROKEN=$countBroken  NOT LINKED=$countMissing"

if ($countBroken -gt 0 -or $countMissing -gt 0) {
    Write-Host ""
    Write-Host "修復するには: make links"
    exit 1
}
