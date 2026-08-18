#!/usr/bin/env pwsh
# ghq-status: ghq 管理リポジトリの git 状態・dev-charter・keep-up-to-date をテーブル表示
#
# 使い方:
#   ghq-status [options]
#
# オプション:
#   -f, --filter PATTERN   リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -a, --all              branch が main かつ git status が clean かつ BRANCHES/DEV-CHARTER が
#                          ハイライトされていないリポジトリも表示する（デフォルトでは非表示）
#   -h, --help             ヘルプを表示
#
# git config:
#   local.status-allowed-remote-branch PATTERN
#       ghq-status の表示上、想定内として扱う origin (remote) ブランチ名(glob可)。ローカル
#       ブランチには適用されない。複数設定可
#       （git config --add local.status-allowed-remote-branch gemini）。
#       BRANCHES 列でベース比率(1/1)から除外し +N 側に計上する（複数登録時は合算して +N）。
#       git-sweep 等の削除処理には影響しない（表示専用の設定）。

Set-StrictMode -Version Latest

function Write-StatusStderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
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

# branch が main かつ git status が clean かつ BRANCHES/DEV-CHARTER が
# ハイライト対象でない（=注目すべき情報がない）行かどうかを判定する
function Test-QuietRow([string]$Branch, [string]$StatusVal, [string]$Br, [string]$Charter, [string]$CharterLatest) {
    if ($Branch -ne 'main') { return $false }
    if ($StatusVal -ne '✓') { return $false }
    if ($Br -notmatch '^1/1([+][0-9]+)?$') { return $false }
    if ($CharterLatest -and $Charter -ne '-' -and $Charter -ne $CharterLatest) { return $false }
    return $true
}

function Write-StatusHeader([string[]]$Cells, [int[]]$Widths) {
    $parts = for ($i = 0; $i -lt $Cells.Count; $i++) {
        "`e[1m" + (Format-TablePad $Cells[$i] $Widths[$i]) + "`e[0m"
    }
    Write-Host ("│ " + ($parts -join " │ ") + " │")
}

function Write-StatusRow([string]$Repo, [string]$Branch, [string]$StatusVal, [string]$Br, [string]$Charter, [string]$Keep, [int[]]$Widths, [string]$CharterLatest) {
    $bc = if ($Br -notmatch '^1/1([+][0-9]+)?$') { "`e[31m" } else { '' }
    $cc = if ($CharterLatest -and $Charter -ne '-' -and $Charter -ne $CharterLatest) { "`e[31m" } else { '' }
    $kc = switch ($Keep) { 'keep' { "`e[32m" } 'skip' { "`e[31m" } default { '' } }

    $line = "│ " + (Format-TablePad $Repo $Widths[0])
    $line += " │ " + (Format-TablePad $Branch $Widths[1])
    $line += " │ " + (Format-TablePad $StatusVal $Widths[2])
    $line += " │ $bc" + (Format-TablePad $Br $Widths[3]) + "`e[0m"
    $line += " │ $cc" + (Format-TablePad $Charter $Widths[4]) + "`e[0m"
    $line += " │ $kc" + (Format-TablePad $Keep $Widths[5]) + "`e[0m │"
    Write-Host $line
}

# ---------- 引数解析 ----------
$FILTER = ''
$SHOW_ALL = $false

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '-f' -or $arg -eq '--filter') {
        if ($i + 1 -ge $args.Count) { Write-StatusStderr "error: --filter requires an argument"; exit 1 }
        $FILTER = $args[$i + 1]
        $i += 2
    } elseif ($arg -eq '-a' -or $arg -eq '--all') {
        $SHOW_ALL = $true
        $i++
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } else {
        Write-StatusStderr "error: unknown option: $arg"
        exit 1
    }
}

# ---------- リポジトリ一覧取得 ----------
$global:LASTEXITCODE = $null
$root = (& ghq root 2>$null)

$allRepoPaths = @(& ghq list -p)

$charterRepo = $allRepoPaths | Where-Object { $_ -match '/dev-charter$' -or $_ -match '\\dev-charter$' } | Select-Object -First 1
$charterLatest = ''
if ($charterRepo) {
    $versionFile = Join-Path $charterRepo 'VERSION'
    if (Test-Path -LiteralPath $versionFile) {
        $charterLatest = (Get-Content -LiteralPath $versionFile -Raw -ErrorAction SilentlyContinue).Trim()
    }
}

$repoList = @($allRepoPaths | Sort-Object)
if ($FILTER) {
    # owner/repo 記法（"/"区切り）でフィルタを書けるよう、Windowsのバックスラッシュ
    # パスを比較用に正規化する（実際のファイル操作には元のパスを使う）
    $repoList = @($repoList | Where-Object { ($_ -replace '\\', '/') -match $FILTER })
}

$allGroups = New-Object System.Collections.Generic.List[string]
$allRepoNames = New-Object System.Collections.Generic.List[string]
$allBranches = New-Object System.Collections.Generic.List[string]
$allStatuses = New-Object System.Collections.Generic.List[string]
$allBrs = New-Object System.Collections.Generic.List[string]
$allCharters = New-Object System.Collections.Generic.List[string]
$allKeeps = New-Object System.Collections.Generic.List[string]

foreach ($repo in $repoList) {
    $rel = $repo
    if ($root -and $repo.StartsWith($root)) {
        $rel = $repo.Substring($root.Length).TrimStart('\', '/')
    }

    $global:LASTEXITCODE = $null
    $branch = (& git -C $repo rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $branch) { $branch = '?' }

    $staged = @(& git -C $repo diff --cached --name-only 2>$null).Count
    $unstaged = @(& git -C $repo diff --name-only 2>$null).Count
    $untracked = @(& git -C $repo ls-files --others --exclude-standard 2>$null).Count
    $stashed = @(& git -C $repo stash list 2>$null).Count

    $global:LASTEXITCODE = $null
    $aheadRaw = (& git -C $repo rev-list --count '@{u}..HEAD' 2>$null)
    $ahead = if ($LASTEXITCODE -eq 0 -and $aheadRaw) { [int]$aheadRaw } else { 0 }
    $global:LASTEXITCODE = $null
    $behindRaw = (& git -C $repo rev-list --count 'HEAD..@{u}' 2>$null)
    $behind = if ($LASTEXITCODE -eq 0 -and $behindRaw) { [int]$behindRaw } else { 0 }

    $statusParts = @()
    if ($staged -gt 0) { $statusParts += "+$staged" }
    if ($unstaged -gt 0) { $statusParts += "!$unstaged" }
    if ($untracked -gt 0) { $statusParts += "?$untracked" }
    if ($stashed -gt 0) { $statusParts += "*$stashed" }
    if ($ahead -gt 0) { $statusParts += "⇡$ahead" }
    if ($behind -gt 0) { $statusParts += "⇣$behind" }
    $statusStr = if ($statusParts.Count -gt 0) { $statusParts -join ' ' } else { '✓' }

    $localBr = @(& git -C $repo branch 2>$null).Count

    $branchRLines = @(& git -C $repo branch -r 2>$null)
    $devCharterBr = @($branchRLines | Where-Object { $_ -match '  dev-charter/' -and $_ -notmatch ' -> ' }).Count

    # git config local.status-allowed-remote-branch (複数可) に登録されたパターンに一致する
    # origin (remote) ブランチは ghq-status の表示上「想定内」とみなし、ベース比率(1/1)から
    # 除外して +N 側に計上する（git-sweep 等の削除処理には影響しない、表示専用の設定）
    $allowedRemotePatterns = @(& git -C $repo config --get-all local.status-allowed-remote-branch 2>$null)
    $originBranchNames = @($branchRLines | Where-Object { $_ -match '  origin/' -and $_ -notmatch ' -> ' } | ForEach-Object {
        $_ -replace '.*origin/', ''
    })

    $originBr = 0
    $allowedRemoteExtra = 0
    foreach ($brName in $originBranchNames) {
        $matched = $false
        foreach ($pat in $allowedRemotePatterns) {
            if ($brName -like $pat) { $matched = $true; break }
        }
        if ($matched) { $allowedRemoteExtra++ } else { $originBr++ }
    }

    $extraBr = $devCharterBr + $allowedRemoteExtra
    $brStr = if ($extraBr -gt 0) { "$localBr/$originBr+$extraBr" } else { "$localBr/$originBr" }

    $charterVerFile = Join-Path $repo 'docs\dev-charter\VERSION'
    $charterVer = if (Test-Path -LiteralPath $charterVerFile) {
        (Get-Content -LiteralPath $charterVerFile -Raw -ErrorAction SilentlyContinue).Trim()
    } else { '-' }
    if (-not $charterVer) { $charterVer = '-' }

    $global:LASTEXITCODE = $null
    $keepRaw = (& git -C $repo config local.keep-up-to-date 2>$null)
    $keepVal = switch ($keepRaw) {
        'true' { 'keep' }
        'false' { 'skip' }
        default { '-' }
    }

    $sepIdx = [Math]::Max($rel.LastIndexOf('\'), $rel.LastIndexOf('/'))
    if ($sepIdx -ge 0) {
        $groupName = $rel.Substring(0, $sepIdx)
        $repoName = $rel.Substring($sepIdx + 1)
    } else {
        $groupName = ''
        $repoName = $rel
    }

    $allGroups.Add($groupName)
    $allRepoNames.Add($repoName)
    $allBranches.Add($branch)
    $allStatuses.Add($statusStr)
    $allBrs.Add($brStr)
    $allCharters.Add($charterVer)
    $allKeeps.Add($keepVal)
}

$activeIdxList = New-Object System.Collections.Generic.List[int]
for ($idx = 0; $idx -lt $allGroups.Count; $idx++) { $activeIdxList.Add($idx) }
$activeIdx = @($activeIdxList)
if (-not $SHOW_ALL) {
    $activeIdx = @($activeIdx | Where-Object {
        -not (Test-QuietRow $allBranches[$_] $allStatuses[$_] $allBrs[$_] $allCharters[$_] $charterLatest)
    })
}

$seenGroups = @(($activeIdx | ForEach-Object { $allGroups[$_] }) | Select-Object -Unique)

$termWidth = Get-TerminalWidth

foreach ($group in $seenGroups) {
    $idxInGroup = @($activeIdx | Where-Object { $allGroups[$_] -eq $group })
    if ($idxInGroup.Count -eq 0) { continue }

    $wRepo = 4; $wBranch = 6; $wStatus = 10; $wBr = 8; $wCharter = 11; $wKeep = 4

    foreach ($idx in $idxInGroup) {
        $w = Get-DisplayWidth $allRepoNames[$idx]; if ($w -gt $wRepo) { $wRepo = $w }
        $w = Get-DisplayWidth $allBranches[$idx]; if ($w -gt $wBranch) { $wBranch = $w }
        $w = Get-DisplayWidth $allStatuses[$idx]; if ($w -gt $wStatus) { $wStatus = $w }
        $w = Get-DisplayWidth $allBrs[$idx]; if ($w -gt $wBr) { $wBr = $w }
        $w = Get-DisplayWidth $allCharters[$idx]; if ($w -gt $wCharter) { $wCharter = $w }
        $w = Get-DisplayWidth $allKeeps[$idx]; if ($w -gt $wKeep) { $wKeep = $w }
    }

    $wRepoMax = $wRepo
    if ($wRepo -gt 20) { $wRepo = 20 }
    $wRepoExpanded = $termWidth - 19 - $wBranch - $wStatus - $wBr - $wCharter - $wKeep
    if ($wRepoExpanded -gt $wRepo) {
        $wRepo = [Math]::Min($wRepoExpanded, $wRepoMax)
    }

    $widths = @($wRepo, $wBranch, $wStatus, $wBr, $wCharter, $wKeep)
    $r1 = Get-TableRule ($wRepo + 2)
    $r2 = Get-TableRule ($wBranch + 2)
    $r3 = Get-TableRule ($wStatus + 2)
    $r4 = Get-TableRule ($wBr + 2)
    $r5 = Get-TableRule ($wCharter + 2)
    $r6 = Get-TableRule ($wKeep + 2)

    Write-Host ($group -replace '[\\/]', ' / ')
    Write-Host "┌$r1┬$r2┬$r3┬$r4┬$r5┬$r6┐"
    Write-StatusHeader @('REPO', 'BRANCH', 'GIT STATUS', 'BRANCHES', 'DEV-CHARTER', 'KEEP') $widths
    Write-Host "├$r1┼$r2┼$r3┼$r4┼$r5┼$r6┤"

    for ($j = 0; $j -lt $idxInGroup.Count; $j++) {
        $idx = $idxInGroup[$j]
        Write-StatusRow $allRepoNames[$idx] $allBranches[$idx] $allStatuses[$idx] $allBrs[$idx] $allCharters[$idx] $allKeeps[$idx] $widths $charterLatest
        if ($j -lt $idxInGroup.Count - 1) {
            Write-Host "├$r1┼$r2┼$r3┼$r4┼$r5┼$r6┤"
        }
    }

    Write-Host "└$r1┴$r2┴$r3┴$r4┴$r5┴$r6┘"
    Write-Host ""
}
