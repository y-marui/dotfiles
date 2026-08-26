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

function Test-LinkSet {
    param(
        [Parameter(Mandatory)] [string]$SourceRoot,
        [Parameter(Mandatory)] [array]$LinkEntries
    )

    foreach ($link in $LinkEntries) {
        $src  = Join-Path $SourceRoot $link.Src
        $dest = $link.Dest

        $item = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue -Force
        if ($item -and $item.LinkType -eq 'SymbolicLink') {
            $target = [string]$item.Target
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $target = Join-Path $item.DirectoryName $target
            }
            if ((Test-Path -LiteralPath $target) -and
                $target.Equals($src, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "  OK         $dest"
                $script:countOk++
            } else {
                Write-Host "  BROKEN     $dest -> $target (期待: $src)"
                $script:countBroken++
            }
        } else {
            Write-Host "  NOT LINKED $dest  (期待: $src)"
            $script:countMissing++
        }
    }
}

Test-LinkSet -SourceRoot $DOTFILES_DIR -LinkEntries $Links
if (Test-Path -LiteralPath $PrivateLinksFile -PathType Leaf) {
    Test-LinkSet -SourceRoot $PRIVATE_DIR -LinkEntries $PrivateLinks
}

Write-Host ""
Write-Host "OK=$countOk  BROKEN=$countBroken  NOT LINKED=$countMissing"

if ($countBroken -gt 0 -or $countMissing -gt 0) {
    Write-Host ""
    Write-Host "修復するには: make links"
    exit 1
}
