#!/usr/bin/env pwsh
# obsidian-project-home: Git repositoryに対応するObsidian Project Homeを一意に解決する
#
# Usage:
#   obsidian-project-home [--repo DIR] [--vault DIR]
#   obsidian-project-home ensure [--repo DIR] [--vault DIR] [--description TEXT]
#   obsidian-project-home check [--vault DIR]
#
# The command compares the current repository's origin with the `repositories`
# frontmatter list in normal-vault `projects/**/*.md` files. GitHub HTTPS, SSH,
# and github-public:/github-private: origin forms normalize to
# https://github.com/owner/repository. It never searches note bodies or private/
# paths. Exit status: 0 unique (or check passed), 3 no mapping, 4 duplicates,
# 5 invalid configuration or frontmatter.
#
# `ensure` resolves like the default mode, and when no Project Home maps to the
# repository it creates one in projects/repositories/ and then re-resolves to
# confirm exactly one mapping. It creates only for repositories whose GitHub owner
# is listed in auto_create_owners (the resolver config, or the
# OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS environment variable; comma separated),
# so cloned third-party repositories never get a note. With no owner listed it
# behaves like the default mode (exit 3). It never overwrites a file, never
# commits, and leaves a created note as a stub for the session-handoff to fill in.
# Creation is reported on stderr as `created: <path>`; stdout is always the path.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Output ($line -replace '^#\s?', '')
    }
}

function Fail([string]$Message, [int]$Code = 5) {
    Write-Stderr "error: $Message"
    exit $Code
}

function Resolve-NormalizedRepository([string]$Value) {
    $value = $Value.Trim().TrimEnd('/')
    if ($value.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }

    $patterns = @(
        '^https?://github\.com/(?<path>.+)$',
        '^ssh://git@github\.com/(?<path>.+)$',
        '^git@github\.com:(?<path>.+)$',
        '^github-(?:public|private):(?<path>.+)$'
    )
    $path = $null
    foreach ($pattern in $patterns) {
        if ($value -match $pattern) {
            $path = $Matches['path'].TrimEnd('/')
            break
        }
    }
    if (-not $path) { return $null }

    $parts = @($path -split '/')
    if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[A-Za-z0-9_.-]+$' -or $parts[1] -notmatch '^[A-Za-z0-9_.-]+$') {
        return $null
    }
    return "https://github.com/$($parts[0].ToLowerInvariant())/$($parts[1].ToLowerInvariant())"
}

function Get-ProjectRepositories([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -eq 0 -or $lines[0] -ne '---') { return @() }

    $repositories = [System.Collections.Generic.List[string]]::new()
    $found = $false
    $collecting = $false
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -eq '---') {
            $collecting = $false
            break
        }

        if ($collecting) {
            if ($line -match '^\s*-\s+(.+)$') {
                $value = $Matches[1].Trim()
                if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                $normalized = Resolve-NormalizedRepository $value
                if (-not $normalized) { throw "invalid repositories frontmatter: $Path" }
                $repositories.Add($normalized)
                continue
            }
            if ($line -match '^\s*(#.*)?$') { continue }
            if ($line -notmatch '^[^\s][^:]*:') { throw "invalid repositories frontmatter: $Path" }
            $collecting = $false
        }

        if ($line -match '^repositories:\s*$') {
            if ($found) { throw "invalid repositories frontmatter: $Path" }
            $found = $true
            $collecting = $true
        } elseif ($line -match '^repositories:\s*\[\]\s*$') {
            if ($found) { throw "invalid repositories frontmatter: $Path" }
            $found = $true
        } elseif ($line -match '^repositories:') {
            throw "invalid repositories frontmatter: $Path"
        }
    }
    if ($collecting) { throw "invalid repositories frontmatter: $Path" }
    return @($repositories)
}

function Get-ConfigPath {
    # ~/.local/bin/dotfiles はこのディレクトリへのシンボリックリンクなので、実体を解決してから
    # リポジトリルートを求める（解決しないと ~/.local-private を探してしまう）。
    $scriptDirItem = Get-Item -LiteralPath $PSScriptRoot -Force
    $realScriptDir = $scriptDirItem.FullName
    if ($scriptDirItem.LinkType) {
        $linkTarget = $scriptDirItem.ResolveLinkTarget($true)
        if ($linkTarget) { $realScriptDir = $linkTarget.FullName }
    }
    # realScriptDir は <dotfiles>\bin\windows なので、リポジトリルートへは二階層上がる
    $dotfilesDir = Split-Path (Split-Path $realScriptDir -Parent) -Parent
    return (Join-Path ($dotfilesDir + '-private') 'obsidian/project-home-resolver.conf')
}

function Get-ConfiguredVault([string]$Override) {
    if ($Override) { return $Override }
    if ($env:OBSIDIAN_VAULT_ROOT) { return $env:OBSIDIAN_VAULT_ROOT }

    $config = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { Fail "resolver config is missing: $config" }

    $configured = $null
    foreach ($rawLine in @(Get-Content -LiteralPath $config)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([^=]+)=(.+)$') { Fail "invalid resolver config: $config" }
        $key = $Matches[1].Trim()
        if ($key -eq 'auto_create_owners') { continue }
        if ($key -ne 'vault_root' -or $configured) { Fail "invalid resolver config: $config" }
        $configured = $Matches[2].Trim()
    }
    if (-not $configured) { Fail "resolver config has no vault_root: $config" }
    if ([System.IO.Path]::IsPathRooted($configured)) { return $configured }
    return (Join-Path $HOME $configured)
}

# ensure が Project Home を自動作成してよい GitHub owner（小文字）。
function Get-AutoCreateOwners {
    $raw = $env:OBSIDIAN_PROJECT_HOME_AUTO_CREATE_OWNERS
    if (-not $raw) {
        $config = Get-ConfigPath
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            foreach ($rawLine in @(Get-Content -LiteralPath $config)) {
                $line = $rawLine.Trim()
                if ($line -like 'auto_create_owners=*') { $raw = $line.Substring($line.IndexOf('=') + 1).Trim() }
            }
        }
    }
    if (-not $raw) { return @() }
    return @($raw -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Get-Mappings([string]$ProjectsDir) {
    $mappings = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $ProjectsDir -File -Filter '*.md' -Recurse | Sort-Object FullName)) {
        foreach ($repository in @(Get-ProjectRepositories $file.FullName)) {
            $mappings.Add([PSCustomObject]@{ Repository = $repository; Path = $file.FullName })
        }
    }
    return $mappings
}

function ConvertTo-YamlQuoted([string]$Text) {
    return '"' + ($Text.Replace('\', '\\').Replace('"', '\"')) + '"'
}

# ${NormalizedOrigin} の雛形 Project Home を作り、そのパスを返す。呼び出し側が再解決して
# 結果を確認するので、誤りがあれば検出して取り消せる。
function New-ProjectHome([string]$VaultDir, [string]$NormalizedOrigin, [string]$Description) {
    $trimmed = $NormalizedOrigin.Substring('https://github.com/'.Length)
    $owner = $trimmed.Split('/')[0]
    $repository = $trimmed.Split('/')[1]

    if (-not $Description) { $Description = "$owner/$repository の現在地を管理する" }
    if ($Description -match "[\r\n]") { Fail '--description must be a single line' 1 }

    $directory = Join-Path (Join-Path $VaultDir 'projects') 'repositories'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $target = Join-Path $directory "$repository.md"
    if (Test-Path -LiteralPath $target) { $target = Join-Path $directory "$owner-$repository.md" }
    if (Test-Path -LiteralPath $target) { Fail "cannot choose a free Project Home file name for $NormalizedOrigin" 5 }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $quoted = ConvertTo-YamlQuoted $Description
    $text = @"
---
type: project
description: $quoted
status: active
created: "$today"
repositories:
  - "$NormalizedOrigin"
---

# $repository

## Outcome

（未記入。完了条件を、session-handoffまたはユーザーが書く）

## Current state

（未記入）

## Next actions

## Decisions

## Open questions

## Key context

- 仕様・使い方は[リポジトリ]($NormalizedOrigin)のREADMEとdocsを正本とする。

## External systems

- [$owner/$repository]($NormalizedOrigin)

## Changelog

- ${today}: Project Homeを自動作成した（内容は未記入）。

"@
    $text = $text -replace "`r`n", "`n"
    # CreateNew は既存ファイルがあると失敗するので、上書きしない。BOMなしUTF-8・LFで書く。
    try {
        $stream = [System.IO.File]::Open($target, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        try {
            $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    } catch {
        Fail "could not create ${target}: $($_.Exception.Message)" 5
    }
    return $target
}

$mode = 'resolve'
$repoDir = (Get-Location).Path
$vaultOverride = $null
$description = ''
for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        'check' {
            if ($mode -ne 'resolve') { Fail 'check may be specified once' 1 }
            $mode = 'check'
        }
        'ensure' {
            if ($mode -ne 'resolve') { Fail 'ensure may be specified once and not with check' 1 }
            $mode = 'ensure'
        }
        '--description' {
            $index++
            if ($index -ge $args.Count) { Fail '--description requires text' 1 }
            $description = $args[$index]
        }
        '--repo' {
            $index++
            if ($index -ge $args.Count) { Fail '--repo requires a directory' 1 }
            $repoDir = $args[$index]
        }
        '--vault' {
            $index++
            if ($index -ge $args.Count) { Fail '--vault requires a directory' 1 }
            $vaultOverride = $args[$index]
        }
        '-h' { Show-Help; exit 0 }
        '--help' { Show-Help; exit 0 }
        default { Fail "unknown argument: $($args[$index])" 1 }
    }
}

try {
    $vaultDir = (Get-ConfiguredVault $vaultOverride)
    $projectsDir = Join-Path $vaultDir 'projects'
    if (-not (Test-Path -LiteralPath $projectsDir -PathType Container)) { Fail "vault projects directory is unavailable: $projectsDir" }
    $vaultDir = (Resolve-Path -LiteralPath $vaultDir).Path

    $mappings = Get-Mappings $projectsDir
} catch {
    Fail $_.Exception.Message 5
}

$duplicates = @($mappings | Group-Object Repository | Where-Object { $_.Count -gt 1 })
if ($mode -eq 'check') {
    if ($duplicates.Count -gt 0) {
        Write-Stderr 'error: duplicate Project Home mappings:'
        foreach ($group in $duplicates | Sort-Object Name) {
            Write-Stderr $group.Name
            foreach ($entry in $group.Group | Sort-Object Path) { Write-Stderr "  $($entry.Path)" }
        }
        exit 4
    }
    Write-Output 'OK: Obsidian Project Home mappings are unique.'
    exit 0
}

try {
    $origin = (& git -C $repoDir config --get remote.origin.url 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $origin) { Fail "origin remote is unavailable: $repoDir" }
    $normalizedOrigin = Resolve-NormalizedRepository $origin
    if (-not $normalizedOrigin) { Fail "unsupported origin remote: $origin" }
} catch {
    Fail $_.Exception.Message 5
}

$hits = @($mappings | Where-Object { $_.Repository -eq $normalizedOrigin } | Sort-Object Path)
if ($hits.Count -eq 0) {
    if ($mode -ne 'ensure') { exit 3 }

    $owner = $normalizedOrigin.Substring('https://github.com/'.Length).Split('/')[0]
    if ((Get-AutoCreateOwners) -notcontains $owner) {
        Write-Stderr "no Project Home maps to $normalizedOrigin and automatic creation is not enabled for $owner"
        exit 3
    }

    $created = New-ProjectHome $vaultDir $normalizedOrigin $description
    # 作った Project Home が、ちょうど自分自身に解決されることを確認してから成功にする。
    try {
        $after = Get-Mappings $projectsDir
    } catch {
        Remove-Item -LiteralPath $created -Force
        Fail "the new Project Home could not be verified; it was removed: $($_.Exception.Message)" 5
    }
    if (@($after | Group-Object Repository | Where-Object { $_.Count -gt 1 }).Count -gt 0) {
        Remove-Item -LiteralPath $created -Force
        Fail 'the new Project Home made the mappings ambiguous; it was removed' 5
    }
    $afterHits = @($after | Where-Object { $_.Repository -eq $normalizedOrigin })
    if ($afterHits.Count -ne 1 -or $afterHits[0].Path -ne $created) {
        Remove-Item -LiteralPath $created -Force
        Fail 'the new Project Home did not resolve to itself; it was removed' 5
    }
    Write-Stderr "created: $created"
    Write-Output $created
    exit 0
}
if ($hits.Count -eq 1) {
    Write-Output $hits[0].Path
    exit 0
}

Write-Stderr "error: multiple Project Homes map to ${normalizedOrigin}:"
foreach ($entry in $hits) { Write-Stderr "  $($entry.Path)" }
exit 4
