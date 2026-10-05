#!/usr/bin/env pwsh
# servers.json にある Copilot CLI user scope MCP を追加・更新する（apply.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\copilot\mcp\servers.json'

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Error: copilot CLI is not installed.')
    exit 1
}

$declared = @(Read-JsonFile -Path $serversFile)
$allActual = Get-Value (Invoke-NativeCapture -Command 'copilot' -Arguments @('mcp', 'list', '--json') | ConvertFrom-Json -AsHashtable) 'mcpServers' @{}
$actual = @{}
foreach ($name in $allActual.Keys) {
    if ((Get-Value $allActual[$name] 'source' $null) -eq 'user') { $actual[$name] = $allActual[$name] }
}

$configPath = Join-Path $HOME '.copilot\mcp-config.json'
$backupPath = Get-BackupPath -Child 'copilot-mcp\mcp-config.json'
$backupCreated = $false

function Backup-Config {
    if ($script:backupCreated -or -not (Test-Path -LiteralPath $configPath)) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    $script:backupCreated = $true
}

function Test-ConfigMatches {
    param($Wanted, $Current)

    return ((Get-Value $Current 'type' $null) -ceq $Wanted['type']) -and
    ((Get-Value $Current 'command' $null) -ceq (Get-Value $Wanted 'command' $null)) -and
    (Test-SameList (Get-Value $Current 'args' @()) (Get-Value $Wanted 'args' @())) -and
    (Test-SameList (Get-Value $Current 'tools' @('*')) (Get-Value $Wanted 'tools' @('*')))
}

$changed = $false
foreach ($entry in $declared) {
    $name = $entry['name']
    $current = Get-Value $actual $name $null
    if ($current -and (Test-ConfigMatches -Wanted $entry -Current $current)) { continue }
    if ($current) {
        Backup-Config
        Write-Host "  replace  $name"
        Invoke-NativeVisible -Command 'copilot' -Arguments @('mcp', 'remove', $name)
    } else {
        Write-Host "  add  $name"
    }

    $arguments = @('mcp', 'add', $name)
    foreach ($tool in @(Get-Value $entry 'tools' @('*'))) { $arguments += @('--tools', $tool) }
    $arguments += @('--', $entry['command']) + @(Get-Value $entry 'args' @())
    Invoke-NativeVisible -Command 'copilot' -Arguments $arguments
    $changed = $true
}

if (-not $changed) {
    Write-Host '  (already up to date)'
} elseif ($backupCreated) {
    Write-Host "  backup  $backupPath"
}
