#!/usr/bin/env pwsh
# servers.json 未記載の user scope MCP を削除する。loopback app MCP は保持する（prune.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\claude\mcp\servers.json'
$claudeJson = Join-Path $HOME '.claude.json'

if (-not (Test-Path -LiteralPath $claudeJson)) {
    Write-Host '  (nothing to prune)'
    exit 0
}

$declared = [string[]]@(@(Read-JsonFile -Path $serversFile) | ForEach-Object { $_['name'] })
$actual = Get-Value (Read-JsonFile -Path $claudeJson) 'mcpServers' @{}
$removeNames = @(Get-SetDifference -A ([string[]]@($actual.Keys)) -B $declared |
        Where-Object { -not (Test-LoopbackUrl (Get-Value $actual[$_] 'url' '')) })
if ($removeNames.Count -eq 0) {
    Write-Host '  (nothing to prune)'
    exit 0
}

$backupPath = Copy-ToBackup -Source $claudeJson -Child 'claude-mcp-pruned.json'
Write-Host "  backup  $backupPath"

foreach ($name in $removeNames) {
    Write-Host "  remove  $name"
    Invoke-NativeVisible -Command 'claude' -Arguments @('mcp', 'remove', '-s', 'user', $name)
}
