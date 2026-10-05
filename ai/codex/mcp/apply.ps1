#!/usr/bin/env pwsh
# servers.json にあって未登録の公式 MCP サーバーを Codex の共通設定へ追加する（apply.sh の PowerShell 版）。

. (Join-Path $PSScriptRoot '..\..\_common.ps1')

$serversFile = Join-Path $DotfilesDir 'ai\codex\mcp\servers.json'

Write-Host '==> Adding missing official MCP servers from servers.json...'
$declared = @(Read-JsonFile -Path $serversFile)

function Get-ActualServers {
    $servers = @{}
    foreach ($entry in @(Invoke-NativeCapture -Command 'codex' -Arguments @('mcp', 'list', '--json') | ConvertFrom-Json -AsHashtable)) {
        $servers[$entry['name']] = $entry
    }
    return $servers
}

$actual = Get-ActualServers
$changed = $false
$configPath = Join-Path (Get-CodexHome) 'config.toml'
$backupPath = Get-BackupPath -Child 'codex-config\config.toml'
$backupCreated = $false

function Backup-Config {
    if (-not (Test-Path -LiteralPath $configPath) -or (Test-Path -LiteralPath $backupPath)) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
    Copy-Item -LiteralPath $configPath -Destination $backupPath
    $script:backupCreated = $true
}

function ConvertTo-TomlString {
    param([string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')
    return '"' + $escaped + '"'
}

# TOML の基本文字列 "..." / リテラル文字列 '...' を値に戻す。
function ConvertFrom-TomlString {
    param([string]$Token)

    if ($Token.StartsWith("'")) { return $Token.Substring(1, $Token.Length - 2) }
    return ($Token | ConvertFrom-Json)
}

$tomlString = '"(?:[^"\\]|\\.)*"|''[^'']*'''
$tomlPair = "($tomlString|[A-Za-z0-9_-]+)\s*=\s*($tomlString)"

# "key" = "value" の並び（インラインテーブルの中身、またはサブテーブルの行）を読む。
function Read-TomlStringPairs {
    param([string]$Text)

    $pairs = @{}
    foreach ($match in [regex]::Matches($Text, $tomlPair)) {
        $key = $match.Groups[1].Value
        if ($key.StartsWith('"') -or $key.StartsWith("'")) { $key = ConvertFrom-TomlString -Token $key }
        $pairs[$key] = ConvertFrom-TomlString -Token $match.Groups[2].Value
    }
    return $pairs
}

function Test-TransportMatches {
    param($Entry, $Current)

    $transport = Get-Value $Current 'transport' @{}
    if ($Entry['type'] -eq 'stdio') {
        return ((Get-Value $transport 'type' $null) -eq 'stdio') -and
        ((Get-Value $transport 'command' $null) -ceq $Entry['command']) -and
        (Test-SameList (Get-Value $transport 'args' @()) (Get-Value $Entry 'args' @()))
    }
    return ((Get-Value $transport 'type' $null) -in @('http', 'streamable_http')) -and
    ((Get-Value $transport 'url' $null) -ceq $Entry['url'])
}

# config.toml の [mcp_servers.NAME] に http_headers を書き込む。変更したら $true。
function Update-HttpAuth {
    param($Entry, $Headers)

    $name = $Entry['name']
    $original = [System.IO.File]::ReadAllText($configPath)
    $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [string[]]@([regex]::Split($original, '(?<=\n)') | Where-Object { $_ -ne '' })

    $table = "[mcp_servers.$name]"
    $subtablePrefix = "[mcp_servers.$name."
    $httpHeadersTable = "[mcp_servers.$name.http_headers]"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $table) { $start = $i; break }
    }
    if ($start -lt 0) { throw "MCP config table was not created: $name" }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].TrimStart()
        if ($trimmed.StartsWith('[') -and -not $trimmed.StartsWith($subtablePrefix)) { $end = $i; break }
    }

    # ネストしたテーブル（[mcp_servers.NAME.http_headers] など）も "[" で始まるため、
    # エントリのテーブルの終端と取り違えず、ブロック単位で読み進める。
    $rootLines = [System.Collections.Generic.List[string]]::new()
    $preservedSubtables = [System.Collections.Generic.List[string]]::new()
    $currentHeaders = @{}
    $currentUrl = $null
    $hasBearer = $false
    $index = $start + 1
    while ($index -lt $end) {
        $line = $lines[$index]
        if ($line.TrimStart().StartsWith($subtablePrefix)) {
            $blockEnd = $end
            for ($i = $index + 1; $i -lt $end; $i++) {
                if ($lines[$i].TrimStart().StartsWith('[')) { $blockEnd = $i; break }
            }
            if ($line.Trim() -eq $httpHeadersTable) {
                if ($blockEnd -gt $index + 1) {
                    $blockText = ($lines[($index + 1)..($blockEnd - 1)] -join '')
                    foreach ($pair in (Read-TomlStringPairs -Text $blockText).GetEnumerator()) {
                        $currentHeaders[$pair.Key] = $pair.Value
                    }
                }
            } else {
                for ($i = $index; $i -lt $blockEnd; $i++) { $preservedSubtables.Add($lines[$i]) }
            }
            $index = $blockEnd
            continue
        }
        $key = if ($line.Contains('=')) { $line.Split('=', 2)[0].Trim() } else { '' }
        $value = if ($line.Contains('=')) { $line.Split('=', 2)[1].Trim() } else { '' }
        switch ($key) {
            'bearer_token_env_var' { if ($value -and $value -notin @('""', "''")) { $hasBearer = $true } }
            'http_headers' {
                foreach ($pair in (Read-TomlStringPairs -Text $value).GetEnumerator()) {
                    $currentHeaders[$pair.Key] = $pair.Value
                }
            }
            'url' { if ($value -match "^($tomlString)") { $currentUrl = ConvertFrom-TomlString -Token $Matches[1] } }
        }
        if ($key -notin @('bearer_token_env_var', 'http_headers')) { $rootLines.Add($line) }
        $index++
    }

    $wantedHeaders = @{}
    foreach ($key in $currentHeaders.Keys) { $wantedHeaders[$key] = $currentHeaders[$key] }
    foreach ($key in $Headers.Keys) { $wantedHeaders[$key] = $Headers[$key] }
    if ($currentUrl -ceq $Entry['url'] -and -not $hasBearer -and (Test-SameTable $currentHeaders $wantedHeaders)) {
        return $false
    }

    $headerItems = (Sort-Ordinal -Items ([string[]]@($wantedHeaders.Keys)) | ForEach-Object {
            "$(ConvertTo-TomlString $_) = $(ConvertTo-TomlString $wantedHeaders[$_])"
        }) -join ', '
    # http_headers は MCP 自身のテーブルにインラインで置く。ネストしたツールのテーブルの
    # 後ろに追記すると、ツール単位の設定になってしまう。
    $replacement = [System.Collections.Generic.List[string]]::new()
    $replacement.Add($lines[$start])
    foreach ($line in $rootLines) { $replacement.Add($line) }
    if ($replacement[$replacement.Count - 1] -notmatch '\n$') {
        $replacement[$replacement.Count - 1] += $newline
    }
    $replacement.Add("http_headers = { $headerItems }$newline")
    foreach ($line in $preservedSubtables) { $replacement.Add($line) }

    $output = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $start; $i++) { $output.Add($lines[$i]) }
    $output.AddRange($replacement)
    for ($i = $end; $i -lt $lines.Count; $i++) { $output.Add($lines[$i]) }
    $updated = $output -join ''

    Backup-Config
    $temporary = Join-Path (Split-Path -Parent $configPath) ".config.toml.$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($temporary, $updated, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $configPath -Force
    return $true
}

foreach ($entry in $declared) {
    $name = $entry['name']
    $current = Get-Value $actual $name $null
    if ($current -and (Test-TransportMatches -Entry $entry -Current $current)) { continue }
    if ($current) {
        Backup-Config
        Write-Host "  replace  $name"
        Invoke-NativeQuiet -Command 'codex' -Arguments @('mcp', 'remove', $name)
    } else {
        Write-Host "  add  $name"
    }
    if ($entry['type'] -eq 'stdio') {
        $arguments = @('mcp', 'add', $name, '--', $entry['command']) + @(Get-Value $entry 'args' @())
    } else {
        $arguments = @('mcp', 'add', $name, '--url', $entry['url'])
    }

    & codex @arguments 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # `codex mcp add --url` は設定を書き込んだ後に OAuth ハンドシェイクを試みる。
        # bearer token 認証だけのサーバーでは失敗しがちだが（認証は後段で書き込む）、
        # エントリ自体は書かれているため、「登録済み」なら成功として扱う。
        if (-not (Get-ActualServers).ContainsKey($name)) {
            throw "codex mcp add failed for $name"
        }
    }
    $changed = $true
}

foreach ($entry in $declared) {
    if ($entry['type'] -ne 'http') { continue }
    $headers = Resolve-HeaderValues -Headers (Get-Value $entry 'headers' @{})
    if ($headers.Count -eq 0) { continue }
    if (Update-HttpAuth -Entry $entry -Headers $headers) {
        Write-Host "  auth update  $($entry['name'])"
        $changed = $true
    }
}

if (-not $changed) {
    Write-Host '  (already up to date)'
} elseif ($backupCreated) {
    Write-Host "  backup  $backupPath"
}
