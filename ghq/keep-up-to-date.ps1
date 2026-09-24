#!/usr/bin/env pwsh
# keep-up-to-date.ps1
# ghq-update の更新対象（各リポジトリの local.keep-up-to-date）を、
# dotfiles-private の宣言ファイルと突き合わせて管理する。
# ghq/keep-up-to-date.sh（macOS / Linux）と同じ判定規則・並び順を使う。
#
# 宣言ファイル（ghq root からの相対パスを1行1件、# 以降はコメント）:
#   <private>\ghq\keep-up-to-date        共通の宣言（sync / merge の書き込み先）
#   <private>\ghq\keep-up-to-date.local  この端末だけの追加分（手編集専用・追加のみ）
# 宣言の集合は上記2ファイルの和集合。パスの大文字小文字は区別しない。
# ghq root に取得されていないリポジトリは、宣言にあっても全動詞で無視する。
#
# 使い方:
#   keep-up-to-date.ps1 diff [--summary]   宣言と実状態の差分を表示（差分があれば終了コード1）
#   keep-up-to-date.ps1 apply              宣言 → 実状態（完全一致。宣言外の true は --unset）
#   keep-up-to-date.ps1 sync               実状態 → 共通宣言（完全一致。取得済みのみ追加・削除）
#   keep-up-to-date.ps1 merge              実状態 → 共通宣言（追加のみ。削除しない）
#   dots ghq {apply|diff|sync|merge}
#
# 環境変数（テスト用の上書き）:
#   GHQ_ROOT               ghq root（ghq 自体も参照する）
#   DOTFILES_PRIVATE_DIR   dotfiles-private の場所（既定: <dotfiles>-private）

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ConfigKey = 'local.keep-up-to-date'

function Write-KeepStderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

$dotfilesDir = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Split-Path -Parent $PSScriptRoot }
$privateDir = if ($env:DOTFILES_PRIVATE_DIR) { $env:DOTFILES_PRIVATE_DIR } else { "$dotfilesDir-private" }
$declFile = Join-Path (Join-Path $privateDir 'ghq') 'keep-up-to-date'
$declLocalFile = "$declFile.local"

$action = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
if ($action -eq '') {
    Write-KeepStderr 'usage: keep-up-to-date.ps1 {apply|diff|sync|merge}'
    exit 1
}
if ($action -notin @('apply', 'diff', 'sync', 'merge')) {
    Write-KeepStderr "error: unknown action: $action"
    exit 1
}
$summary = $false
foreach ($argument in @($args | Select-Object -Skip 1)) {
    if ($argument -eq '--summary') {
        if ($action -ne 'diff') {
            Write-KeepStderr 'error: --summary は diff でのみ使えます'
            exit 1
        }
        $summary = $true
    } else {
        Write-KeepStderr "error: unknown option: $argument"
        exit 1
    }
}

# --summary（dots check 用）は、対象外の環境では何も出さずに正常終了する。
function Stop-Unavailable([string]$Message) {
    if ($summary) { exit 0 }
    Write-KeepStderr "error: $Message"
    exit 1
}

if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
    Stop-Unavailable "'ghq' が見つかりません。"
}
if (-not (Test-Path -LiteralPath $declFile)) {
    Stop-Unavailable "宣言ファイルがありません: $declFile"
}

# 宣言ファイルの1行を比較用のキー（コメント・空白・末尾スラッシュを除去し小文字化）へ。
function ConvertTo-Key([string]$Line) {
    $key = ($Line -replace '#.*$', '').Trim()
    $key = ($key -replace '\\', '/') -replace '/+$', ''
    return $key.ToLowerInvariant()
}

function Get-DeclKeys([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { ConvertTo-Key $_ } |
            Where-Object { $_ -ne '' } |
            Sort-Object -Unique
    )
}

# sort -f（LC_ALL=C）と同じ順序にするため、大文字へ畳んだ文字列を序数比較する。
function Sort-Entries([string[]]$Entries) {
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $Entries) { $list.Add($entry) }
    $list.Sort([System.Comparison[string]] {
        param($a, $b)
        [string]::CompareOrdinal($a.ToUpperInvariant(), $b.ToUpperInvariant())
    })
    return @($list)
}

$ghqRoot = (@(& ghq root) | Select-Object -First 1) -replace '\\', '/'
$ghqRoot = $ghqRoot.TrimEnd('/')

# 取得済みリポジトリ: キー -> @{ Path; Rel }
$fetched = @{}
foreach ($path in @(& ghq list -p)) {
    $norm = $path -replace '\\', '/'
    $prefix = "$ghqRoot/"
    $rel = if ($norm.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $norm.Substring($prefix.Length)
    } else {
        $norm
    }
    $fetched[$rel.ToLowerInvariant()] = [pscustomobject]@{ Path = $path; Rel = $rel }
}
$fetchedKeys = @($fetched.Keys)

# 実状態が true のもの（取得済みのみ）
$trueKeys = @(
    foreach ($key in $fetchedKeys) {
        $value = (& git -C $fetched[$key].Path config --local --bool --get $ConfigKey 2>$null)
        if ($value -eq 'true') { $key }
    }
)

$mainKeys = @(Get-DeclKeys $declFile)
$localKeys = @(Get-DeclKeys $declLocalFile)
$declaredKeys = @(($mainKeys + $localKeys) | Sort-Object -Unique)

# 宣言なし: 実状態は true だが、共通・端末固有どちらの宣言にもない
$plus = @($trueKeys | Where-Object { $declaredKeys -notcontains $_ } | Sort-Object)
# 未適用: 宣言済みで取得済みだが true でない
$minus = @($declaredKeys | Where-Object { ($fetchedKeys -contains $_) -and ($trueKeys -notcontains $_) })
# sync で共通宣言から外す: 共通宣言にあり、取得済みで true でない
$mainStale = @($mainKeys | Where-Object { ($fetchedKeys -contains $_) -and ($trueKeys -notcontains $_) })

function Get-Rels([string[]]$Keys) {
    $rels = @()
    if ($null -ne $Keys) {
        foreach ($key in $Keys) { $rels += $fetched[$key].Rel }
    }
    return $rels
}

function Invoke-Diff {
    if ($summary) {
        if ($plus.Count -gt 0 -or $minus.Count -gt 0) {
            Write-Host "+$($plus.Count) 宣言なし / -$($minus.Count) 未適用"
            exit 1
        }
        exit 0
    }

    if ($plus.Count -eq 0 -and $minus.Count -eq 0) {
        Write-Host "No diff: 宣言と各リポジトリの $ConfigKey は一致しています。"
        return
    }
    if ($plus.Count -gt 0) {
        Write-Host "$ConfigKey=true だが宣言なし (+actual のみ):"
        foreach ($rel in (Sort-Entries (Get-Rels $plus))) { Write-Host "  [+actual]  $rel" }
        Write-Host ''
    }
    if ($minus.Count -gt 0) {
        Write-Host "宣言済みだが $ConfigKey が true でない (-file のみ):"
        foreach ($rel in (Sort-Entries (Get-Rels $minus))) { Write-Host "  [-file]  $rel" }
    }
    exit 1
}

# 共通宣言ファイルを書き戻す。コメント・空行は先頭にまとめ、エントリは重複を除いて
# 大文字小文字を無視してソートする。
function Write-Decl([string[]]$RemoveKeys, [string[]]$AddRels) {
    $header = New-Object 'System.Collections.Generic.List[string]'
    $entries = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($line in @(Get-Content -LiteralPath $declFile)) {
        if ($line -match '^\s*(#|$)') {
            $header.Add($line)
            continue
        }
        $key = ConvertTo-Key $line
        if (($RemoveKeys -contains $key) -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $entries.Add($line)
    }
    foreach ($rel in $AddRels) { $entries.Add($rel) }

    $lines = @($header) + @(Sort-Entries @($entries | Where-Object { $_ -ne '' }))
    $text = (($lines -join "`n") + "`n")
    [System.IO.File]::WriteAllText($declFile, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# sync / merge の共通処理: 共通宣言へ追加（plus）し、必要なら外す（mainStale）。
function Invoke-WriteDecl([bool]$DoRemove) {
    $add = @(Get-Rels $plus)
    $removeKeys = @(if ($DoRemove) { $mainStale })
    $remove = @(Get-Rels $removeKeys)

    foreach ($rel in $add) { Write-Host "[add]    $rel" }
    foreach ($rel in $remove) { Write-Host "[remove] $rel" }
    if ($add.Count -eq 0 -and $remove.Count -eq 0) {
        Write-Host 'No change: 共通宣言はすでに実状態と整合しています。'
        return
    }
    Write-Decl $removeKeys $add
    Write-Host ''
    Write-Host "keep-up-to-date ${action}: +$($add.Count) added / -$($remove.Count) removed"
}

function Invoke-Apply {
    $nSet = 0
    $nUnset = 0
    foreach ($key in $minus) {
        & git -C $fetched[$key].Path config --local --bool $ConfigKey true
        if ($LASTEXITCODE -ne 0) { throw "git config failed: $($fetched[$key].Rel)" }
        Write-Host "[set]    $($fetched[$key].Rel)"
        $nSet++
    }
    foreach ($key in $plus) {
        & git -C $fetched[$key].Path config --local --unset $ConfigKey
        if ($LASTEXITCODE -ne 0) { throw "git config --unset failed: $($fetched[$key].Rel)" }
        Write-Host "[unset]  $($fetched[$key].Rel)"
        $nUnset++
    }

    if ($nSet -eq 0 -and $nUnset -eq 0) {
        Write-Host 'No change: 宣言はすでに各リポジトリへ適用済みです。'
        return
    }
    Write-Host ''
    Write-Host "keep-up-to-date apply: $nSet set / $nUnset unset"
}

switch ($action) {
    'diff' { Invoke-Diff }
    'apply' { Invoke-Apply }
    'sync' { Invoke-WriteDecl $true }
    'merge' { Invoke-WriteDecl $false }
}
