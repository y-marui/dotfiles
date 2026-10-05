#!/usr/bin/env pwsh
# apply.ps1
# plugins.json にあって未導入の marketplace / plugin を追加する（apply.sh の PowerShell 版）
#
# 動作:
#   1. ~/.claude/plugins/{installed_plugins,known_marketplaces}.json を直接読む
#   2. 不足している marketplace を追加
#   3. 不足している plugin をインストール
#   4. 未宣言のものは削除しない
#
# 使い方:
#   pwsh ai/claude/plugin/apply.ps1
#   dots claude apply --plugin-only

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$pluginsFile = Join-Path $DotfilesDir 'ai\claude\plugin\plugins.json'
$installedJson = Join-Path $HOME '.claude\plugins\installed_plugins.json'
$marketplacesJson = Join-Path $HOME '.claude\plugins\known_marketplaces.json'

Write-Host '==> Adding missing marketplaces / plugins from plugins.json...'
$declared = Read-JsonFile -Path $pluginsFile
$actualMkt = [string[]]@((Read-JsonFileOrEmpty -Path $marketplacesJson).Keys)
$actualPlugins = [string[]]@((Get-Value (Read-JsonFileOrEmpty -Path $installedJson) 'plugins' @{}).Keys)

$missingMkt = @(@(Get-Value $declared 'marketplaces' @()) | Where-Object { $_['name'] -notin $actualMkt })
$missingPlugins = @(@(Get-Value $declared 'plugins' @()) | Where-Object { $_ -notin $actualPlugins })

if ($missingMkt.Count -eq 0 -and $missingPlugins.Count -eq 0) {
    Write-Host '  (already up to date)'
    exit 0
}

foreach ($marketplace in $missingMkt) {
    Write-Host "  marketplace add  $($marketplace['name'])"
    Invoke-NativeQuiet -Command 'claude' -Arguments @('plugin', 'marketplace', 'add', $marketplace['repo'])
}

foreach ($plugin in $missingPlugins) {
    Write-Host "  install  $plugin"
    Invoke-NativeQuiet -Command 'claude' -Arguments @('plugin', 'install', '-s', 'user', $plugin)
}
