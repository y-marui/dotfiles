#!/usr/bin/env pwsh
# plugins.json 未記載の Claude Code plugin / marketplace を削除する（prune.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$pluginsFile = Join-Path $DotfilesDir 'ai\claude\plugin\plugins.json'
$installedJson = Join-Path $HOME '.claude\plugins\installed_plugins.json'
$marketplacesJson = Join-Path $HOME '.claude\plugins\known_marketplaces.json'

$declared = Read-JsonFile -Path $pluginsFile
$declaredPlugins = [string[]]@(Get-Value $declared 'plugins' @())
$declaredMarketplaces = [string[]]@(@(Get-Value $declared 'marketplaces' @()) | ForEach-Object { $_['name'] })
$actualPlugins = [string[]]@((Get-Value (Read-JsonFileOrEmpty -Path $installedJson) 'plugins' @{}).Keys)
$actualMarketplaces = [string[]]@((Read-JsonFileOrEmpty -Path $marketplacesJson).Keys)
$removePlugins = @(Get-SetDifference -A $actualPlugins -B $declaredPlugins)
$removeMarketplaces = @(Get-SetDifference -A $actualMarketplaces -B $declaredMarketplaces)

if ($removePlugins.Count -eq 0 -and $removeMarketplaces.Count -eq 0) {
    Write-Host '  (nothing to prune)'
    exit 0
}

foreach ($name in $removePlugins) {
    Write-Host "  uninstall  $name"
    Invoke-NativeVisible -Command 'claude' -Arguments @('plugin', 'uninstall', '-s', 'user', '--keep-data', $name)
}
foreach ($name in $removeMarketplaces) {
    Write-Host "  marketplace remove  $name"
    Invoke-NativeVisible -Command 'claude' -Arguments @('plugin', 'marketplace', 'remove', '--scope', 'user', $name)
}
