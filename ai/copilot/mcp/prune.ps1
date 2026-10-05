#!/usr/bin/env pwsh
# servers.json に記載のない Copilot CLI user scope MCP を削除する（prune.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\copilot\mcp\servers.json'

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Error: copilot CLI is not installed.')
    exit 1
}

$declared = [string[]]@(@(Read-JsonFile -Path $serversFile) | ForEach-Object { $_['name'] })
$actual = Get-Value (Invoke-NativeCapture -Command 'copilot' -Arguments @('mcp', 'list', '--json') | ConvertFrom-Json -AsHashtable) 'mcpServers' @{}
$userNames = [string[]]@($actual.Keys | Where-Object { (Get-Value $actual[$_] 'source' $null) -eq 'user' })
$removeNames = @(Get-SetDifference -A $userNames -B $declared)
if ($removeNames.Count -eq 0) {
    Write-Host '  (nothing to prune)'
    exit 0
}

$configPath = Join-Path $HOME '.copilot\mcp-config.json'
if (Test-Path -LiteralPath $configPath) {
    $backupPath = Copy-ToBackup -Source $configPath -Child 'copilot-mcp-pruned\mcp-config.json'
    Write-Host "  backup  $backupPath"
}

foreach ($name in $removeNames) {
    Write-Host "  remove  $name"
    Invoke-NativeVisible -Command 'copilot' -Arguments @('mcp', 'remove', $name)
}
