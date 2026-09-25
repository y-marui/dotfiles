#!/usr/bin/env pwsh
# WingetPinの宣言に実際のwinget pin状態を一致させる。
#
# 判定の前にWingetPin.cache（実際のpin状態のスナップショット。gitignore対象）を更新する。
#   -NoPrune    宣言済みをpinするだけで、未宣言のpinは解除しない（dots winget apply --no-prune）
#   -PruneOnly  未宣言のpinを解除するだけで、pinはしない（dots winget prune）
#   -DryRun     pin状態を変更せず、実行した場合の変更予定だけを表示する

param(
    [switch]$NoPrune,
    [switch]$PruneOnly,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($NoPrune -and $PruneOnly) {
    throw '-NoPrune と -PruneOnly は同時に指定できません'
}

$pinFile = Join-Path $PSScriptRoot 'WingetPin'
$cacheFile = Join-Path $PSScriptRoot 'WingetPin.cache'
$cacheScript = Join-Path $PSScriptRoot 'update_wingetpin_cache.ps1'

function Get-DeclaredIds {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
            Where-Object { $_ -ne '' }
    ) | Sort-Object -Unique
}

# キャッシュが古いと、手動で変更したpinを見落とすため、判定の前に更新する。
& pwsh -NoLogo -NoProfile -File $cacheScript | Out-Null
if ($LASTEXITCODE -ne 0) { throw "update_wingetpin_cache.ps1 failed with exit code $LASTEXITCODE" }

$declared = @(Get-DeclaredIds $pinFile)
$actual = @(Get-DeclaredIds $cacheFile)
$tag = if ($DryRun) { '[dry-run] ' } else { '' }
$changed = 0

if (-not $PruneOnly) {
    foreach ($id in $declared) {
        if ($actual -notcontains $id) {
            Write-Host "  ${tag}pin    $id"
            $changed++
            if (-not $DryRun) {
                & winget pin add --id $id --exact
                if ($LASTEXITCODE -ne 0) { throw "winget pin add failed for $id" }
            }
        }
    }
}

$unmanaged = @($actual | Where-Object { $declared -notcontains $_ })
if ($NoPrune) {
    if ($unmanaged.Count -gt 0) {
        Write-Host '--no-prune: 未宣言のpinは解除しません（dots winget prune で解除）:'
        foreach ($id in $unmanaged) { Write-Host "  $id" }
    }
} else {
    foreach ($id in $unmanaged) {
        Write-Host "  ${tag}unpin  $id"
        $changed++
        if (-not $DryRun) {
            & winget pin remove --id $id --exact
            if ($LASTEXITCODE -ne 0) { throw "winget pin remove failed for $id" }
        }
    }
}

if ($changed -eq 0) {
    Write-Host 'No change: WingetPinはすでに実際のpin状態と一致しています。'
} elseif ($DryRun) {
    Write-Host '[dry-run] pin状態は変更していません'
}

if (-not $DryRun) {
    & pwsh -NoLogo -NoProfile -File $cacheScript | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "update_wingetpin_cache.ps1 failed with exit code $LASTEXITCODE" }
}
