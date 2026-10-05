#!/usr/bin/env pwsh
# servers.json 未記載の直接登録 MCP を削除する。plugin/app 由来は保持する（prune.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\codex\mcp\servers.json'

$declared = [string[]]@(@(Read-JsonFile -Path $serversFile) | ForEach-Object { $_['name'] })
$actual = @{}
foreach ($entry in @(Invoke-NativeCapture -Command 'codex' -Arguments @('mcp', 'list', '--json') | ConvertFrom-Json -AsHashtable)) {
    $actual[$entry['name']] = $entry
}
$plugins = @(Get-Value (Invoke-NativeCapture -Command 'codex' -Arguments @('plugin', 'list', '--json') | ConvertFrom-Json -AsHashtable) 'installed' @())

$pluginOwned = [System.Collections.Generic.HashSet[string]]::new()
foreach ($plugin in $plugins) {
    $sourcePath = Get-Value (Get-Value $plugin 'source' @{}) 'path' $null
    if (-not (Get-Value $plugin 'installed' $true) -or -not $sourcePath) { continue }
    try {
        $manifest = Read-JsonFile -Path (Join-Path $sourcePath '.mcp.json')
    } catch {
        continue
    }
    foreach ($name in (Get-Value $manifest 'mcpServers' @{}).Keys) { [void]$pluginOwned.Add($name) }
}

function Test-Retained {
    param([string]$Name)

    $transport = Get-Value $actual[$Name] 'transport' @{}
    return $pluginOwned.Contains($Name) -or
    ([string](Get-Value $transport 'command' '')).StartsWith('/Applications/ChatGPT.app/') -or
    (Test-LoopbackUrl (Get-Value $transport 'url' ''))
}

$removeNames = @(Get-SetDifference -A ([string[]]@($actual.Keys)) -B $declared |
        Where-Object { -not (Test-Retained -Name $_) })
if ($removeNames.Count -eq 0) {
    Write-Host '  (nothing to prune)'
    exit 0
}

$configPath = Join-Path (Get-CodexHome) 'config.toml'
if (Test-Path -LiteralPath $configPath) {
    $backupPath = Copy-ToBackup -Source $configPath -Child 'codex-mcp-pruned\config.toml'
    Write-Host "  backup  $backupPath"
}

foreach ($name in $removeNames) {
    Write-Host "  remove  $name"
    Invoke-NativeVisible -Command 'codex' -Arguments @('mcp', 'remove', $name)
}
