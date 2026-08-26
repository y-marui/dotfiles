#!/usr/bin/env pwsh
# ghq-status: ghq 管理リポジトリの git 状態・dev-charter・keep-up-to-date をテーブル表示
#
# 使い方:
#   ghq-status [options]
#
# オプション:
#   -f, --filter PATTERN          リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -a, --all                     branch が保護ブランチ（リポジトリの .gitattributes の
#                                 repo-protected-branches）かつ git status が
#                                 clean かつ BRANCHES/DEV-CHARTER がハイライトされていない
#                                 リポジトリも表示する（デフォルトでは非表示）
#   --ignore-charter-outdated     DEV-CHARTER が古いことによるハイライト・強制表示を無視する
#   --no-ignore-charter-outdated  DEV-CHARTER が古い場合にハイライト・強制表示する（無視しない）
#   -h, --help                    ヘルプを表示
#
# --ignore-charter-outdated / --no-ignore-charter-outdated を省略した場合のデフォルトは
# git config local.status-ignore-charter-outdated（true/false）に従う。
#
# ブランチ方針（.gitattributes）:
#   * repo-main-branch=develop
#   * repo-protected-branches=main,develop
#   * repo-remote-only-branches=lite
# repo-protected-branches はローカル・origin双方、repo-remote-only-branches はoriginだけに
# 存在することを期待する。属性未設定時だけ local.repo-main-branch、
# local.repo-protected-branches、local.repo-remote-only-branches をfallbackとして使う。
# 旧 git-sweep-main / git-sweep-protected 属性と
# local.status-allowed-remote-branch（glob・複数可）も互換fallbackとして読み取る。
#
# その他のgit config:
#   local.status-ignore-charter-outdated true/false
#       DEV-CHARTER 列が古い（charter_latest より古い）場合の赤色ハイライトと、
#       -a 無指定時の強制表示（quiet row 扱いにしない挙動）を無視するかどうかの
#       デフォルト値。CLI の --ignore-charter-outdated / --no-ignore-charter-outdated
#       で都度上書きできる。git config が一切未設定の場合のスクリプト側フォールバックは
#       false（従来通りハイライト・強制表示する）だが、dotfiles 配布の
#       git/gitconfig（[local] セクション）でデフォルト true（無視する）を設定済み。
#
# BRANCHES 列はローカル/originの実測数を表示する。main+developがprotected、liteが
# remote-onlyなら正常値は1+1/1+2。数だけでなくブランチ名と配置も検証するため、
# liteがローカルにもある、または別名ブランチに置き換わった場合もハイライトする。

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

function Get-RepoAttr([string]$Repo, [string]$Attr) {
    $global:LASTEXITCODE = $null
    $output = (& git -C $Repo check-attr $Attr -- . 2>$null)
    if ($output -match ": ${Attr}: (.+)$") { return $Matches[1] }
    return $null
}

function Get-RepoConfigValue([string]$Repo, [string]$Key) {
    $global:LASTEXITCODE = $null
    $value = (& git -C $Repo config --get $Key 2>$null)
    if ($LASTEXITCODE -eq 0 -and $value) { return $value.Trim() }
    return $null
}

function ConvertFrom-BranchCsv([string]$Csv) {
    if (-not $Csv) { return @() }
    return @($Csv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
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

# branch が保護ブランチ（main+develop 運用なら develop も含む）かつ git status が
# clean かつ BRANCHES/DEV-CHARTER がハイライト対象でない（=注目すべき情報がない）
# 行かどうかを判定する
function Test-QuietRow([bool]$IsProtected, [string]$StatusVal, [string]$Br, [string]$ExpectedBr, [bool]$PolicyOk, [string]$Charter, [string]$CharterLatest, [bool]$IgnoreCharter) {
    if (-not $IsProtected) { return $false }
    if ($StatusVal -ne '✓') { return $false }
    if (-not $PolicyOk) { return $false }
    if ($Br -notmatch "^${ExpectedBr}`$") { return $false }
    if (-not $IgnoreCharter -and $CharterLatest -and $Charter -ne '-' -and $Charter -ne $CharterLatest) { return $false }
    return $true
}

function Write-StatusHeader([string[]]$Cells, [int[]]$Widths) {
    $parts = for ($i = 0; $i -lt $Cells.Count; $i++) {
        "`e[1m" + (Format-TablePad $Cells[$i] $Widths[$i]) + "`e[0m"
    }
    Write-Host ("│ " + ($parts -join " │ ") + " │")
}

function Write-StatusRow([string]$Repo, [string]$Branch, [string]$StatusVal, [string]$Br, [string]$Charter, [string]$Keep, [int[]]$Widths, [string]$CharterLatest, [string]$ExpectedBr, [bool]$PolicyOk, [bool]$IsProtected, [bool]$IgnoreCharter) {
    $branchColor = if (-not $IsProtected) { "`e[31m" } else { '' }
    $statusColor = if ($StatusVal -ne '✓') { "`e[31m" } else { '' }
    $bc = if (-not $PolicyOk -or $Br -notmatch "^${ExpectedBr}`$") { "`e[31m" } else { '' }
    $cc = if (-not $IgnoreCharter -and $CharterLatest -and $Charter -ne '-' -and $Charter -ne $CharterLatest) { "`e[31m" } else { '' }
    $kc = switch ($Keep) { 'keep' { "`e[32m" } 'skip' { "`e[90m" } default { '' } }

    $line = "│ " + (Format-TablePad $Repo $Widths[0])
    $line += " │ $branchColor" + (Format-TablePad $Branch $Widths[1]) + "`e[0m"
    $line += " │ $statusColor" + (Format-TablePad $StatusVal $Widths[2]) + "`e[0m"
    $line += " │ $bc" + (Format-TablePad $Br $Widths[3]) + "`e[0m"
    $line += " │ $cc" + (Format-TablePad $Charter $Widths[4]) + "`e[0m"
    $line += " │ $kc" + (Format-TablePad $Keep $Widths[5]) + "`e[0m │"
    Write-Host $line
}

# ---------- 引数解析 ----------
$FILTER = ''
$SHOW_ALL = $false
$IGNORE_CHARTER_ARG = $null

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
    } elseif ($arg -eq '--ignore-charter-outdated') {
        $IGNORE_CHARTER_ARG = $true
        $i++
    } elseif ($arg -eq '--no-ignore-charter-outdated') {
        $IGNORE_CHARTER_ARG = $false
        $i++
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } else {
        Write-StatusStderr "error: unknown option: $arg"
        exit 1
    }
}

if ($null -ne $IGNORE_CHARTER_ARG) {
    $IGNORE_CHARTER = $IGNORE_CHARTER_ARG
} else {
    $global:LASTEXITCODE = $null
    $ignoreCharterRaw = (& git config --bool local.status-ignore-charter-outdated 2>$null)
    $IGNORE_CHARTER = ($ignoreCharterRaw -eq 'true')
}

# ---------- リポジトリ一覧取得 ----------
$global:LASTEXITCODE = $null
$root = (& ghq root 2>$null)

$allRepoPaths = @(& ghq list -p)

$charterRepo = $allRepoPaths | Where-Object { $_ -match '/dev-charter$' -or $_ -match '\\dev-charter$' } | Select-Object -First 1
$charterLatest = ''
if ($charterRepo) {
    # ローカルの checkout 中ブランチではなく main の VERSION を基準にする
    $global:LASTEXITCODE = $null
    $charterLatestLines = @(& git -C $charterRepo show main:VERSION 2>$null)
    if ($LASTEXITCODE -eq 0 -and $charterLatestLines.Count -gt 0) {
        $charterLatest = (($charterLatestLines -join "`n").Trim())
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
$allBases = New-Object System.Collections.Generic.List[string]
$allProtected = New-Object System.Collections.Generic.List[bool]
$allPolicyOk = New-Object System.Collections.Generic.List[bool]

foreach ($repo in $repoList) {
    $rel = $repo
    if ($root -and $repo.StartsWith($root)) {
        $rel = $repo.Substring($root.Length).TrimStart('\', '/')
    }

    $global:LASTEXITCODE = $null
    $branch = (& git -C $repo rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $branch) { $branch = '?' }

    $mainBranch = Get-RepoAttr $repo 'repo-main-branch'
    if (-not $mainBranch -or $mainBranch -eq 'unspecified') {
        $mainBranch = Get-RepoAttr $repo 'git-sweep-main'
    }
    if (-not $mainBranch -or $mainBranch -eq 'unspecified') {
        $mainBranch = Get-RepoConfigValue $repo 'local.repo-main-branch'
    }
    if (-not $mainBranch) {
        $originHead = (& git -C $repo symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $originHead) {
            $originHead = $originHead -replace '^origin/', ''
            & git -C $repo show-ref --verify --quiet "refs/remotes/origin/$originHead"
            if ($LASTEXITCODE -eq 0) { $mainBranch = $originHead }
        }
    }
    if (-not $mainBranch) { $mainBranch = 'main' }

    $protectedRaw = Get-RepoAttr $repo 'repo-protected-branches'
    if (-not $protectedRaw -or $protectedRaw -eq 'unspecified') {
        $protectedRaw = Get-RepoAttr $repo 'git-sweep-protected'
    }
    if (-not $protectedRaw -or $protectedRaw -eq 'unspecified') {
        $protectedRaw = Get-RepoConfigValue $repo 'local.repo-protected-branches'
    }
    $protectedList = @(if ($protectedRaw -and $protectedRaw -ne 'unspecified') {
        @(ConvertFrom-BranchCsv $protectedRaw)
    } else {
        @($mainBranch)
        if ($mainBranch -ne 'main') {
            & git -C $repo show-ref --verify --quiet refs/heads/main
            $hasMain = ($LASTEXITCODE -eq 0)
            if (-not $hasMain) {
                & git -C $repo show-ref --verify --quiet refs/remotes/origin/main
                $hasMain = ($LASTEXITCODE -eq 0)
            }
            if ($hasMain) { 'main' }
        }
    })
    if ($protectedList -notcontains $mainBranch) { $protectedList += $mainBranch }

    $remoteOnlyRaw = Get-RepoAttr $repo 'repo-remote-only-branches'
    if (-not $remoteOnlyRaw -or $remoteOnlyRaw -eq 'unspecified') {
        $remoteOnlyRaw = Get-RepoConfigValue $repo 'local.repo-remote-only-branches'
    }
    $legacyRemotePatterns = @()
    if ($remoteOnlyRaw -and $remoteOnlyRaw -ne 'unspecified') {
        $remoteOnlyList = @(ConvertFrom-BranchCsv $remoteOnlyRaw)
    } else {
        $remoteOnlyList = @()
        $legacyRemotePatterns = @(& git -C $repo config --get-all local.status-allowed-remote-branch 2>$null)
    }
    $base = $protectedList.Count
    $isProtected = $protectedList -contains $branch

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

    $branchRLines = @(& git -C $repo branch -r 2>$null)
    $localBranchNames = @(& git -C $repo branch --format='%(refname:short)' 2>$null)
    $originBranchNames = @($branchRLines | Where-Object { $_ -match '  origin/' -and $_ -notmatch ' -> ' } | ForEach-Object {
        $_ -replace '.*origin/', ''
    })

    $localBr = $localBranchNames.Count
    $originBr = $originBranchNames.Count
    $policyOk = $true
    $legacyRemoteExtra = 0
    foreach ($expected in $protectedList) {
        if ($localBranchNames -notcontains $expected -or $originBranchNames -notcontains $expected) { $policyOk = $false }
    }
    foreach ($expected in $remoteOnlyList) {
        if ($localBranchNames -contains $expected -or $originBranchNames -notcontains $expected) { $policyOk = $false }
    }
    foreach ($brName in $localBranchNames) {
        if ($protectedList -notcontains $brName) { $policyOk = $false }
    }
    foreach ($brName in $originBranchNames) {
        $matched = ($protectedList -contains $brName -or $remoteOnlyList -contains $brName)
        if (-not $matched) {
            foreach ($pat in $legacyRemotePatterns) {
                if ($brName -like $pat) {
                    $matched = $true
                    $legacyRemoteExtra++
                    break
                }
            }
        }
        if (-not $matched) { $policyOk = $false }
    }

    $remoteOnlyExpected = $remoteOnlyList.Count + $legacyRemoteExtra

    # baseExtra（PROTECTED のうち main 以外の数、develop 運用なら 1）が 0 なら
    # 従来通りの "local/origin[+N]" 表示のまま。1 以上（main+develop 等の複数
    # ブランチ恒久運用）なら "1" の基準と実測の追加分を "1+N" の形に分解して
    # 表示する。ローカル・リモートそれぞれの N が独立して見えるので、develop が
    # 片方にしか無い異常（例: "1+1/1+0"）も判別できる
    $baseExtra = $base - 1
    if ($baseExtra -gt 0) {
        $localExtraActual = $localBr - 1
        $originExtraActual = $originBr - 1
        $brStr = "1+$localExtraActual/1+$originExtraActual"
        $expectedBr = "1\+$baseExtra/1\+$($baseExtra + $remoteOnlyExpected)"
    } else {
        $brStr = "$localBr/$originBr"
        $expectedBr = "1/$($base + $remoteOnlyExpected)"
    }

    $charterVerFile = Join-Path $repo 'docs\dev-charter\VERSION'
    $charterVer = if (Test-Path -LiteralPath $charterVerFile) {
        (Get-Content -LiteralPath $charterVerFile -Raw -ErrorAction SilentlyContinue).Trim()
    } else { '-' }
    if (-not $charterVer) { $charterVer = '-' }

    $global:LASTEXITCODE = $null
    $keepRaw = (& git -C $repo config local.keep-up-to-date 2>$null)
    $keepVal = switch ($keepRaw) {
        'true' { 'keep' }
        default { 'skip' }
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
    $allBases.Add($expectedBr)
    $allProtected.Add($isProtected)
    $allPolicyOk.Add($policyOk)
}

$activeIdxList = New-Object System.Collections.Generic.List[int]
for ($idx = 0; $idx -lt $allGroups.Count; $idx++) { $activeIdxList.Add($idx) }
$activeIdx = @($activeIdxList)
if (-not $SHOW_ALL) {
    $activeIdx = @($activeIdx | Where-Object {
        -not (Test-QuietRow $allProtected[$_] $allStatuses[$_] $allBrs[$_] $allBases[$_] $allPolicyOk[$_] $allCharters[$_] $charterLatest $IGNORE_CHARTER)
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
        Write-StatusRow $allRepoNames[$idx] $allBranches[$idx] $allStatuses[$idx] $allBrs[$idx] $allCharters[$idx] $allKeeps[$idx] $widths $charterLatest $allBases[$idx] $allPolicyOk[$idx] $allProtected[$idx] $IGNORE_CHARTER
        if ($j -lt $idxInGroup.Count - 1) {
            Write-Host "├$r1┼$r2┼$r3┼$r4┼$r5┼$r6┤"
        }
    }

    Write-Host "└$r1┴$r2┴$r3┴$r4┴$r5┴$r6┘"
    Write-Host ""
}
