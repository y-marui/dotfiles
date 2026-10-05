#!/usr/bin/env pwsh
# 共通・agent 専用の管理ファイルと、実際に探索される個人 skill の差分を表示する（diff.sh の PowerShell 版）。
#
# 使い方:
#   pwsh ai/skills/diff.ps1 -Agent claude            # 差分を詳細表示
#   pwsh ai/skills/diff.ps1 -Agent codex -Summary    # 1行サマリーのみ出力

param(
    [Parameter(Mandatory)]
    [ValidateSet('claude', 'codex')]
    [string]$Agent,
    [switch]$Summary
)

. (Join-Path $PSScriptRoot '..\_common.ps1')

$skillHome = Get-SkillHome -Agent $Agent
$cacheHome = Get-SkillCacheHome

$sources = [System.Collections.Generic.List[object]]::new()
foreach ($entry in (Get-ExternalSkills -Agent $Agent)) {
    $sources.Add([pscustomobject]@{ Name = $entry['name']; Dir = (Join-Path $cacheHome $entry['name']) })
}
foreach ($source in (Get-LocalSkillSources -Agent $Agent)) { $sources.Add($source) }

$duplicateNames = @(Get-DuplicateNames -Sources $sources)
if ($duplicateNames.Count -gt 0) {
    [Console]::Error.WriteLine("共通 skill と $Agent 専用 skill で名前が重複しています:")
    [Console]::Error.WriteLine(($duplicateNames -join "`n"))
    exit 1
}

$declared = [System.Collections.Generic.List[string]]::new()
$mismatch = [System.Collections.Generic.List[string]]::new()
$sourceMissing = [System.Collections.Generic.List[string]]::new()
foreach ($source in ($sources | Sort-Object { $_.Name } -CaseSensitive)) {
    $declared.Add($source.Name)
    if (-not (Test-Path -LiteralPath (Join-Path $source.Dir 'SKILL.md') -PathType Leaf)) {
        $sourceMissing.Add($source.Name)
    }
    $destination = Join-Path $skillHome $source.Name
    if (-not (Test-PathOrLink -Path $destination)) {
        $mismatch.Add($source.Name)
    } elseif (-not (Test-SamePath (Get-LinkTarget -Path $destination) $source.Dir)) {
        $mismatch.Add($source.Name)
    }
}

function Get-SkillNames {
    param([string]$Directory, [string[]]$Exclude = @())

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    $names = foreach ($item in (Get-ChildItem -LiteralPath $Directory -Force)) {
        if ($item.Name -in $Exclude) { continue }
        $isLink = $item.LinkType -eq 'SymbolicLink'
        if ($isLink -or (Test-Path -LiteralPath (Join-Path $item.FullName 'SKILL.md') -PathType Leaf)) {
            $item.Name
        }
    }
    return @($names)
}

$actual = [string[]]@(Get-SkillNames -Directory $skillHome)

# Codex の正規追加先は ~/.agents/skills。~/.codex/skills は Codex 自身や
# skill-installer が使うため、apply では触らず .system 以外を追加済み skill として検知する。
$codexInstalled = @()
if ($Agent -eq 'codex') {
    $codexInstalled = @(Sort-Ordinal -Items ([string[]]@(Get-SkillNames -Directory (Join-Path $HOME '.codex\skills') -Exclude @('.system')) | Select-Object -Unique))
}

$declaredNames = [string[]]@($declared | Select-Object -Unique)
$mismatched = @(Sort-Ordinal -Items ([string[]]@($mismatch | Select-Object -Unique)))
$sourceMissingNames = @(Sort-Ordinal -Items ([string[]]@($sourceMissing | Select-Object -Unique)))
$onlyActual = @(Get-SetDifference -A $actual -B $declaredNames)
$onlyFiles = @(Get-SetDifference -A $declaredNames -B $actual)
$found = ($onlyActual.Count + $onlyFiles.Count + $mismatched.Count + $codexInstalled.Count + $sourceMissingNames.Count) -gt 0

if ($Summary) {
    $parts = @()
    if ($onlyActual.Count -gt 0) { $parts += "+$($onlyActual.Count) actual のみ" }
    if ($onlyFiles.Count -gt 0) { $parts += "-$($onlyFiles.Count) files のみ" }
    if ($mismatched.Count -gt 0) { $parts += "~$($mismatched.Count) link 不一致" }
    if ($codexInstalled.Count -gt 0) { $parts += "+$($codexInstalled.Count) ~/.codex/skills" }
    if ($sourceMissingNames.Count -gt 0) { $parts += "~$($sourceMissingNames.Count) source 不足" }
    if ($parts.Count -gt 0) { Write-Host ($parts -join ' / ') }
    Exit-Diff -Found $found
}

if (-not $found) {
    $agentLabel = if ($Agent -eq 'claude') { 'Claude Code' } else { 'Codex' }
    $location = if ($Agent -eq 'claude') { '~/.claude/skills' } else { '~/.agents/skills' }
    Write-Host "No diff: 管理対象の共通・${agentLabel}専用 skill と $location は一致しています。"
    exit 0
}

if ($onlyActual.Count -gt 0) {
    Write-Host '追加済みだが dotfiles 未記載 (+actual のみ):'
    foreach ($name in $onlyActual) { Write-Host "  [+actual]  $name" }
    Write-Host ''
}
if ($onlyFiles.Count -gt 0) {
    Write-Host 'dotfiles にあるが未配置 (-files のみ):'
    foreach ($name in $onlyFiles) { Write-Host "  [-files]  $name" }
    Write-Host ''
}
if ($mismatched.Count -gt 0) {
    Write-Host '管理対象だがリンク先が不一致 (~link):'
    foreach ($name in $mismatched) { Write-Host "  [~link]    $name" }
    Write-Host ''
}
if ($codexInstalled.Count -gt 0) {
    Write-Host 'Codex 側で追加されている skill (~/.codex/skills、.system は除外):'
    foreach ($name in $codexInstalled) { Write-Host "  [+codex]   $name" }
    Write-Host ''
}
if ($sourceMissingNames.Count -gt 0) {
    Write-Host '外部 skill の取得元がありません (~source):'
    foreach ($name in $sourceMissingNames) { Write-Host "  [~source]  $name" }
}

exit 1
