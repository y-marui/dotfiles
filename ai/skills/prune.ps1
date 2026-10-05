#!/usr/bin/env pwsh
# 宣言から外れた dotfiles 所有の skill リンクと外部 skill キャッシュを退避する（prune.sh の PowerShell 版）。

param(
    [Parameter(Mandatory)]
    [ValidateSet('claude', 'codex')]
    [string]$Agent
)

. (Join-Path $PSScriptRoot '..\_common.ps1')

$skillHome = Get-SkillHome -Agent $Agent
$cacheHome = Get-SkillCacheHome
$backupDir = Get-BackupPath -Child "ai-skills-pruned\$Agent"
$changed = $false

$declared = [string[]]@(@(Get-LocalSkillSources -Agent $Agent) | ForEach-Object { $_.Name }) +
[string[]]@(@(Get-ExternalSkills -Agent $Agent) | ForEach-Object { $_['name'] })

$ownedRoots = @(
    (Join-Path $DotfilesDir 'ai\skills'),
    (Join-Path $DotfilesDir "ai\$Agent\skills"),
    $cacheHome
)

if (Test-Path -LiteralPath $skillHome -PathType Container) {
    foreach ($item in (Get-ChildItem -LiteralPath $skillHome -Force)) {
        if ($item.LinkType -ne 'SymbolicLink') { continue }
        if ($item.Name -in $declared) { continue }
        $target = Get-LinkTarget -Path $item.FullName
        if (-not ($ownedRoots | Where-Object { Test-UnderPath -Path $target -Root $_ })) { continue }
        $scope = "$(Split-Path -Leaf (Split-Path -Parent $skillHome))-$(Split-Path -Leaf $skillHome)"
        $backupPath = Join-Path $backupDir "links\$scope\$($item.Name)"
        Move-ToBackup -Path $item.FullName -Destination $backupPath
        Write-Host "  BACKUP  $($item.FullName) -> $backupPath"
        $changed = $true
    }
}

# どちらの agent からも参照されず、宣言にもない専用キャッシュだけを退避する。
$allExternal = [string[]]@(@(Get-ExternalSkills -All) | ForEach-Object { $_['name'] })

if (Test-Path -LiteralPath $cacheHome -PathType Container) {
    foreach ($sourceDir in (Get-ChildItem -LiteralPath $cacheHome -Directory)) {
        $name = $sourceDir.Name
        if ($name.StartsWith('.') -or $name -in $allExternal) { continue }
        $referenced = $false
        foreach ($destination in @((Join-Path $HOME ".agents\skills\$name"), (Join-Path $HOME ".claude\skills\$name"))) {
            if (Test-SamePath (Get-LinkTarget -Path $destination) $sourceDir.FullName) { $referenced = $true }
        }
        if ($referenced) { continue }
        $backupPath = Join-Path $backupDir "external\$name"
        Move-ToBackup -Path $sourceDir.FullName -Destination $backupPath
        $stateFile = Join-Path $cacheHome ".sources\$name"
        if (Test-Path -LiteralPath $stateFile) {
            Move-ToBackup -Path $stateFile -Destination (Join-Path $backupDir "external\$name.source")
        }
        Write-Host "  BACKUP  $($sourceDir.FullName) -> $backupPath"
        $changed = $true
    }
}

if (-not $changed) {
    Write-Host '  (nothing to prune)'
}
