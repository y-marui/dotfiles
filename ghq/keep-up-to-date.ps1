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
#                                          （宣言なし・ghq なし・想定外の失敗などのエラーは終了コード2）
#   keep-up-to-date.ps1 apply [--no-prune] [--dry-run]
#                                          宣言 → 実状態（完全一致。宣言外の true は --unset）。
#                                          --no-prune は宣言済みを true にするだけで --unset しない
#   keep-up-to-date.ps1 prune [--dry-run]  宣言にない true を --unset するだけ（true にはしない）
#   keep-up-to-date.ps1 sync [--dry-run] [--yes]
#                                          実状態 → 共通宣言（完全一致。取得済みのみ追加・削除）。
#                                          共通宣言から削除する場合は --yes が必要
#   keep-up-to-date.ps1 merge [--dry-run]  実状態 → 共通宣言（追加のみ。削除しない）
#   --dry-run は何も変更せず、実行した場合の変更予定だけを表示する
#   dots ghq {apply|diff|sync|merge|prune}
#
# 環境変数（テスト用の上書き）:
#   GHQ_ROOT               ghq root（ghq 自体も参照する）
#   DOTFILES_PRIVATE_DIR   dotfiles-private の場所（既定: <dotfiles>-private）

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 想定外の失敗は、差分あり（終了コード1）と区別できるよう終了コード2にする。
trap {
    [Console]::Error.WriteLine("error: $_")
    exit 2
}

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
    Write-KeepStderr 'usage: keep-up-to-date.ps1 {apply|diff|sync|merge|prune}'
    exit 2
}
if ($action -notin @('apply', 'diff', 'sync', 'merge', 'prune')) {
    Write-KeepStderr "error: unknown action: $action"
    exit 2
}
$summary = $false
$noPrune = $false
$dryRun = $false
$yes = $false
foreach ($argument in @($args | Select-Object -Skip 1)) {
    switch ($argument) {
        '--summary' {
            if ($action -ne 'diff') {
                Write-KeepStderr 'error: --summary は diff でのみ使えます'
                exit 2
            }
            $summary = $true
        }
        '--no-prune' {
            if ($action -ne 'apply') {
                Write-KeepStderr 'error: --no-prune は apply でのみ使えます'
                exit 2
            }
            $noPrune = $true
        }
        '--dry-run' {
            if ($action -eq 'diff') {
                Write-KeepStderr 'error: --dry-run は diff では使えません'
                exit 2
            }
            $dryRun = $true
        }
        '--yes' {
            if ($action -ne 'sync') {
                Write-KeepStderr 'error: --yes は sync でのみ使えます'
                exit 2
            }
            $yes = $true
        }
        default {
            Write-KeepStderr "error: unknown option: $argument"
            exit 2
        }
    }
}

# --summary（dots check 用）は、対象外の環境では何も出さずに正常終了する。
function Stop-Unavailable([string]$Message) {
    if ($summary) { exit 0 }
    Write-KeepStderr "error: $Message"
    exit 2
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

# 複数の ghq root が設定されていても、各リポジトリを所属する root からの相対パスにする。
$ghqRoots = @(& ghq root --all | ForEach-Object { ($_ -replace '\\', '/').TrimEnd('/') })

# 取得済みリポジトリ: キー -> @{ Path; Rel }
$fetched = @{}
foreach ($path in @(& ghq list -p)) {
    $norm = $path -replace '\\', '/'
    $rel = $norm
    foreach ($root in $ghqRoots) {
        $prefix = "$root/"
        if ($norm.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $norm.Substring($prefix.Length)
            break
        }
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
    if ($dryRun) {
        Write-Host ''
        Write-Host '[dry-run] 共通宣言は変更していません'
        return
    }
    if ($remove.Count -gt 0 -and -not $yes) {
        Write-KeepStderr 'error: 共通宣言から上記のエントリを削除します。実行するには --yes を付けてください'
        Write-KeepStderr '  （削除せず追加だけ行う場合は dots ghq merge）'
        exit 2
    }
    Write-Decl $removeKeys $add
    Write-Host ''
    Write-Host "keep-up-to-date ${action}: +$($add.Count) added / -$($remove.Count) removed"
}

# apply: 宣言済みを true にし（minus）、宣言外の true を --unset する（plus）。
# prune: --unset だけ行う。--no-prune（apply）: true にするだけで --unset しない。
# --dry-run は git config を書き換えず、予定だけを表示する。
function Invoke-Apply([string]$Mode) {
    $nSet = 0
    $nUnset = 0
    $tag = if ($dryRun) { '[dry-run] ' } else { '' }

    if ($Mode -eq 'apply') {
        foreach ($key in $minus) {
            if (-not $dryRun) {
                & git -C $fetched[$key].Path config --local --bool $ConfigKey true
                if ($LASTEXITCODE -ne 0) { throw "git config failed: $($fetched[$key].Rel)" }
            }
            Write-Host "${tag}[set]    $($fetched[$key].Rel)"
            $nSet++
        }
    }
    if ($noPrune) {
        if ($plus.Count -gt 0) {
            Write-Host "--no-prune: 宣言にない $ConfigKey=true は解除しません（dots ghq prune で解除）:"
            foreach ($rel in (Sort-Entries (Get-Rels $plus))) { Write-Host "  $rel" }
        }
    } else {
        foreach ($key in $plus) {
            if (-not $dryRun) {
                & git -C $fetched[$key].Path config --local --unset $ConfigKey
                if ($LASTEXITCODE -ne 0) { throw "git config --unset failed: $($fetched[$key].Rel)" }
            }
            Write-Host "${tag}[unset]  $($fetched[$key].Rel)"
            $nUnset++
        }
    }

    if ($nSet -eq 0 -and $nUnset -eq 0) {
        if ($Mode -eq 'prune') {
            Write-Host "No change: 宣言にない $ConfigKey はありません。"
        } else {
            Write-Host 'No change: 宣言はすでに各リポジトリへ適用済みです。'
        }
        return
    }
    Write-Host ''
    Write-Host "keep-up-to-date ${Mode}: $nSet set / $nUnset unset"
    if ($dryRun) {
        Write-Host "[dry-run] 各リポジトリの $ConfigKey は変更していません"
    }
}

switch ($action) {
    'diff' { Invoke-Diff }
    'apply' { Invoke-Apply 'apply' }
    'prune' { Invoke-Apply 'prune' }
    'sync' { Invoke-WriteDecl $true }
    'merge' { Invoke-WriteDecl $false }
}
