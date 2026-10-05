#!/usr/bin/env pwsh
# apply.ps1
# servers.json にあって未登録の MCP サーバーを `claude mcp add -s user` で追加する（apply.sh の PowerShell 版）
#
# 動作:
#   1. ~/.claude.json を直接読み、servers.json と異なる user scope 登録を追加・更新
#   2. 未宣言のサーバー（IDE・Claude.app等が動的に追加した分）は削除しない
#   3. ヘッダーの値（シークレット）は cmd で都度生成し、コマンドラインには表示しない
#
# 使い方:
#   pwsh ai/claude/mcp/apply.ps1
#   dots claude apply --mcp-only

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\claude\mcp\servers.json'
$claudeJson = Join-Path $HOME '.claude.json'

Write-Host '==> Adding missing MCP servers from servers.json...'
$declared = @(Read-JsonFile -Path $serversFile)
$actual = Get-Value (Read-JsonFileOrEmpty -Path $claudeJson) 'mcpServers' @{}

$resolvedHeaders = @{}
foreach ($entry in $declared) {
    $resolvedHeaders[$entry['name']] = Resolve-HeaderValues -Headers (Get-Value $entry 'headers' @{})
}

function Test-ConfigMatches {
    param($Entry, $Current)

    if ($Entry['type'] -eq 'stdio') {
        return ((Get-Value $Current 'type' 'stdio') -eq 'stdio') -and
        ((Get-Value $Current 'command' $null) -ceq $Entry['command']) -and
        (Test-SameList (Get-Value $Current 'args' @()) (Get-Value $Entry 'args' @()))
    }
    return ((Get-Value $Current 'type' $null) -in @('http', 'sse')) -and
    ((Get-Value $Current 'url' $null) -ceq $Entry['url']) -and
    (Test-SameTable (Get-Value $Current 'headers' @{}) $resolvedHeaders[$Entry['name']])
}

$changedEntries = @($declared | Where-Object {
        -not (Test-ConfigMatches -Entry $_ -Current (Get-Value $actual $_['name'] @{}))
    })
if ($changedEntries.Count -eq 0) {
    Write-Host '  (already up to date)'
    exit 0
}

if (Test-Path -LiteralPath $claudeJson) {
    $backupPath = Copy-ToBackup -Source $claudeJson -Child 'claude-mcp\config.json'
    Write-Host "  backup  $backupPath"
}

foreach ($entry in $changedEntries) {
    $name = $entry['name']
    if ($actual.Contains($name)) {
        Write-Host "  replace  $name"
        Invoke-NativeQuiet -Command 'claude' -Arguments @('mcp', 'remove', '-s', 'user', $name)
    } else {
        Write-Host "  add  $name"
    }
    $arguments = @('mcp', 'add', '-s', 'user')
    if ($entry['type'] -eq 'stdio') {
        $arguments += @($name, '--', $entry['command']) + @(Get-Value $entry 'args' @())
    } else {
        $arguments += @('--transport', 'http', $name, $entry['url'])
        foreach ($headerName in $resolvedHeaders[$name].Keys) {
            $arguments += @('-H', "${headerName}: $($resolvedHeaders[$name][$headerName])")
        }
    }
    # secret を含みうるため引数自体は表示しない
    Invoke-NativeQuiet -Command 'claude' -Arguments $arguments
}
