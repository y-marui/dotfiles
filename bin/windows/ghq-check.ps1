#!/usr/bin/env pwsh
# ghq-check: GitHub の全リポジトリの取得状況を確認し、必要に応じて ghq get で取得する
#
# 使い方:
#   ghq-check [options]
#
# オプション:
#   --sync              未取得リポジトリを ghq get で取得する
#   --dry-run           --sync の実行対象を表示するだけで ghq get は実行しない
#   --all               アーカイブ済みリポジトリも含めて表示する
#   --no-forks          フォークリポジトリを除外
#   --exclude PATTERN   名前（owner/repo）に一致するパターンを除外（複数指定可）
#   -f, --filter PATTERN  名前（owner/repo）が正規表現 PATTERN にマッチするものだけを対象にする
#   --existing          ローカルに取得済みのリポジトリのみ表示する
#   --missing           ローカルに未取得のリポジトリのみ表示する
#   -h, --help          ヘルプを表示

Set-StrictMode -Version Latest

function Write-CheckStderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

# ---------- 引数解析 ----------
$SYNC = $false
$DRY_RUN = $false
$ALL = $false
$NO_FORKS = $false
$EXCLUDE_PATTERNS = New-Object System.Collections.Generic.List[string]
$FILTER = ''
$SHOW_EXISTING = $true
$SHOW_MISSING = $true

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '--sync') { $SYNC = $true; $i++ }
    elseif ($arg -eq '--dry-run') { $DRY_RUN = $true; $i++ }
    elseif ($arg -eq '--all') { $ALL = $true; $i++ }
    elseif ($arg -eq '--no-forks') { $NO_FORKS = $true; $i++ }
    elseif ($arg -eq '--exclude') {
        if ($i + 1 -ge $args.Count) { Write-CheckStderr "error: --exclude requires an argument"; exit 1 }
        $EXCLUDE_PATTERNS.Add($args[$i + 1])
        $i += 2
    }
    elseif ($arg -eq '-f' -or $arg -eq '--filter') {
        if ($i + 1 -ge $args.Count) { Write-CheckStderr "error: --filter requires an argument"; exit 1 }
        $FILTER = $args[$i + 1]
        $i += 2
    }
    elseif ($arg -eq '--existing') { $SHOW_MISSING = $false; $i++ }
    elseif ($arg -eq '--missing') { $SHOW_EXISTING = $false; $i++ }
    elseif ($arg -eq '-h' -or $arg -eq '--help') { Show-Help; exit 0 }
    else { Write-CheckStderr "error: unknown option: $arg"; exit 1 }
}

# ---------- 依存確認 ----------
foreach ($cmd in @('gh', 'ghq')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-CheckStderr "error: '$cmd' が見つかりません。インストールしてください。"
        exit 1
    }
}

# ---------- 表示幅（East Asian Width 概算） ----------
function Get-DisplayWidth([string]$Text) {
    $width = 0
    foreach ($rune in $Text.EnumerateRunes()) {
        $cp = $rune.Value
        if (($cp -ge 0x1100 -and $cp -le 0x115F) -or
            $cp -eq 0x2329 -or $cp -eq 0x232A -or
            ($cp -ge 0x2E80 -and $cp -le 0xA4CF -and $cp -ne 0x303F) -or
            ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
            ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or
            ($cp -ge 0xFF00 -and $cp -le 0xFF60) -or
            ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
            ($cp -ge 0x20000 -and $cp -le 0x3FFFD)) {
            $width += 2
        } else {
            $width += 1
        }
    }
    return $width
}

# ---------- テーブル描画 ----------
function Format-TablePad([string]$Str, [int]$Width) {
    $w = Get-DisplayWidth $Str
    if ($w -gt $Width) {
        $truncated = ''
        $curWidth = 0
        foreach ($rune in $Str.EnumerateRunes()) {
            $chStr = [char]::ConvertFromUtf32($rune.Value)
            $chWidth = Get-DisplayWidth $chStr
            if ($curWidth + $chWidth -gt $Width - 1) { break }
            $truncated += $chStr
            $curWidth += $chWidth
        }
        $Str = "$truncated…"
        $w = Get-DisplayWidth $Str
    }
    return $Str + (' ' * [Math]::Max(0, $Width - $w))
}

function Get-TableRule([int]$Width) {
    return [string]::new('─', $Width)
}

function Get-TerminalWidth {
    if ($env:COLUMNS) { return [int]$env:COLUMNS }
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 0) { return $w }
    } catch {}
    return 80
}

function Show-CheckSection([int]$TermWidth, [bool]$IsArchived) {
    $dim = if ($IsArchived) { "`e[2;3m" } else { '' }

    $names = New-Object System.Collections.Generic.List[string]
    $statuses = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Script:ResultNames.Count; $i++) {
        if ($Script:ResultArchived[$i] -ne $IsArchived) { continue }
        $names.Add($Script:ResultNames[$i])
        $statuses.Add($Script:ResultStatuses[$i])
    }
    if ($names.Count -eq 0) { return }

    $wRepo = 4
    $wSt = 6
    foreach ($name in $names) { $w = Get-DisplayWidth $name; if ($w -gt $wRepo) { $wRepo = $w } }
    foreach ($st in $statuses) { $w = Get-DisplayWidth $st; if ($w -gt $wSt) { $wSt = $w } }

    $wExp = $TermWidth - 13 - $wSt
    if ($wExp -gt $wRepo) { $wRepo = $wExp }

    $r1 = Get-TableRule ($wRepo + 2)
    $r2 = Get-TableRule ($wSt + 2)

    Write-Host "┌$r1┬$r2┐"
    Write-Host ("│ `e[1m" + (Format-TablePad 'REPO' $wRepo) + "`e[0m │ `e[1m" + (Format-TablePad 'STATUS' $wSt) + "`e[0m │")
    Write-Host "├$r1┼$r2┤"

    for ($j = 0; $j -lt $names.Count; $j++) {
        $color = switch ($statuses[$j]) {
            'fetched' { "`e[31m" }
            'missing' { "`e[32m" }
            default { '' }
        }
        Write-Host ("$dim│ " + (Format-TablePad $names[$j] $wRepo) + " │ $dim$color" + (Format-TablePad $statuses[$j] $wSt) + "`e[0m$dim │`e[0m")
        if ($j -lt $names.Count - 1) {
            Write-Host "├$r1┼$r2┤"
        }
    }

    Write-Host "└$r1┴$r2┘"
    Write-Host ""
}

function Show-CheckTable {
    $termWidth = Get-TerminalWidth
    Show-CheckSection $termWidth $false

    foreach ($archived in $Script:ResultArchived) {
        if ($archived) {
            Write-Host "`e[2;3mArchived`e[0m"
            Show-CheckSection $termWidth $true
            break
        }
    }
}

# ---------- gh api graphql --paginate の連結JSONを分割 ----------
function Split-ConcatenatedJson([string]$Text) {
    $objects = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $inString = $false
    $escape = $false
    $start = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inString) {
            if ($escape) { $escape = $false }
            elseif ($c -eq '\') { $escape = $true }
            elseif ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') { $inString = $true }
        elseif ($c -eq '{') {
            if ($depth -eq 0) { $start = $i }
            $depth++
        } elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $objects.Add($Text.Substring($start, $i - $start + 1))
            }
        }
    }
    return $objects
}

# ---------- リポジトリ一覧取得 ----------
Write-CheckStderr "GitHub からリポジトリ一覧を取得中..."

$gqlQuery = @'
query($endCursor: String) {
  viewer {
    repositories(first: 100, after: $endCursor, ownerAffiliations: OWNER) {
      pageInfo { hasNextPage endCursor }
      nodes { nameWithOwner isArchived isFork }
    }
  }
}
'@

$raw = & gh api graphql --paginate -f "query=$gqlQuery" 2>$null
$allRepos = New-Object System.Collections.Generic.List[pscustomobject]
foreach ($jsonText in (Split-ConcatenatedJson ($raw -join "`n"))) {
    $page = $jsonText | ConvertFrom-Json
    foreach ($node in $page.data.viewer.repositories.nodes) {
        $allRepos.Add($node)
    }
}

# ---------- フィルタリング ----------
$filtered = $allRepos
if (-not $ALL) {
    $filtered = @($filtered | Where-Object { -not $_.isArchived })
}
if ($NO_FORKS) {
    $filtered = @($filtered | Where-Object { -not $_.isFork })
}
foreach ($pattern in $EXCLUDE_PATTERNS) {
    $filtered = @($filtered | Where-Object { $_.nameWithOwner -notmatch $pattern })
}
if ($FILTER) {
    $filtered = @($filtered | Where-Object { $_.nameWithOwner -match $FILTER })
}

$repos = @($filtered | Sort-Object -Property nameWithOwner)

if ($repos.Count -eq 0) {
    Write-CheckStderr "対象リポジトリが見つかりませんでした。"
    exit 0
}

Write-CheckStderr "対象: $($repos.Count) リポジトリ"

$global:LASTEXITCODE = $null
$ghqRoot = (& ghq root 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $ghqRoot) { $ghqRoot = Join-Path $HOME 'ghq' }

function Test-GhqFetched([string]$Repo) {
    return Test-Path -LiteralPath (Join-Path $ghqRoot "github.com\$Repo") -PathType Container
}

# ---------- 表示・実行 ----------
$Script:ResultNames = New-Object System.Collections.Generic.List[string]
$Script:ResultStatuses = New-Object System.Collections.Generic.List[string]
$Script:ResultArchived = New-Object System.Collections.Generic.List[bool]

if (-not $SYNC -and -not $DRY_RUN) {
    foreach ($r in $repos) {
        $rowSt = if (Test-GhqFetched $r.nameWithOwner) { 'fetched' } else { 'missing' }
        if ($rowSt -eq 'fetched' -and -not $SHOW_EXISTING) { continue }
        if ($rowSt -eq 'missing' -and -not $SHOW_MISSING) { continue }
        $Script:ResultNames.Add($r.nameWithOwner)
        $Script:ResultArchived.Add([bool]$r.isArchived)
        $Script:ResultStatuses.Add($rowSt)
    }
    Show-CheckTable
    exit 0
}

if ($DRY_RUN) {
    foreach ($r in $repos) {
        $rowFetched = Test-GhqFetched $r.nameWithOwner
        if ($rowFetched -and -not $SHOW_EXISTING) { continue }
        if (-not $rowFetched -and -not $SHOW_MISSING) { continue }
        $Script:ResultNames.Add($r.nameWithOwner)
        $Script:ResultArchived.Add([bool]$r.isArchived)
        $Script:ResultStatuses.Add($(if ($rowFetched) { 'skip' } else { 'get' }))
    }
    Show-CheckTable
    exit 0
}

# --sync: ghq get 実行 ----------
$fetchedCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($r in $repos) {
    $rowFetched = Test-GhqFetched $r.nameWithOwner
    if ($rowFetched -and -not $SHOW_EXISTING) { continue }
    if (-not $rowFetched -and -not $SHOW_MISSING) { continue }

    $Script:ResultNames.Add($r.nameWithOwner)
    $Script:ResultArchived.Add([bool]$r.isArchived)
    if ($rowFetched) {
        Write-CheckStderr "  skip  $($r.nameWithOwner)"
        $Script:ResultStatuses.Add('skip')
        $skippedCount++
    } else {
        [Console]::Error.Write("  get   $($r.nameWithOwner) ... ")
        $global:LASTEXITCODE = $null
        & ghq get --silent "github.com/$($r.nameWithOwner)" *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-CheckStderr "done"
            $Script:ResultStatuses.Add('fetched')
            $fetchedCount++
        } else {
            Write-CheckStderr "FAILED"
            $Script:ResultStatuses.Add('FAILED')
            $failedCount++
        }
    }
}

Write-CheckStderr ""
Show-CheckTable
Write-Host "完了: 取得 $fetchedCount / スキップ $skippedCount / 失敗 $failedCount"
