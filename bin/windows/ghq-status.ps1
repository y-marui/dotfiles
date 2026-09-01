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
#   -p, --paths-only              異常のあるリポジトリ（デフォルト表示される行）の
#                                 フルパスだけを1行ずつ出力する。テーブル表示はせず、
#                                 -a は無視する（常に異常のあるリポジトリのみ）。
#                                 他コマンドからパイプで使うためのもの
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
# その他のgit config / 環境変数:
#   local.status-ignore-charter-outdated true/false
#       DEV-CHARTER 列が古い（charter_latest より古い）場合の赤色ハイライトと、
#       -a 無指定時の強制表示（quiet row 扱いにしない挙動）を無視するかどうかの
#       デフォルト値。CLI の --ignore-charter-outdated / --no-ignore-charter-outdated
#       で都度上書きできる。git config が一切未設定の場合のスクリプト側フォールバックは
#       false（従来通りハイライト・強制表示する）だが、dotfiles 配布の
#       git/gitconfig（[local] セクション）でデフォルト true（無視する）を設定済み。
#   GHQ_STATUS_JOBS
#       リポジトリ情報を並列取得するワーカー数。デフォルトは8。
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
$PATHS_ONLY = $false
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
    } elseif ($arg -eq '-p' -or $arg -eq '--paths-only') {
        $PATHS_ONLY = $true
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
$allPaths = New-Object System.Collections.Generic.List[string]

$jobs = 8
if ($env:GHQ_STATUS_JOBS) {
    $parsedJobs = 0
    if (-not [int]::TryParse($env:GHQ_STATUS_JOBS, [ref]$parsedJobs) -or $parsedJobs -lt 1) {
        Write-StatusStderr 'error: GHQ_STATUS_JOBS must be a positive integer'
        exit 1
    }
    $jobs = $parsedJobs
}

$workItems = @(for ($repoIndex = 0; $repoIndex -lt $repoList.Count; $repoIndex++) {
    [PSCustomObject]@{ Index = $repoIndex; Repo = $repoList[$repoIndex] }
})

$repoData = @($workItems | ForEach-Object -Parallel {
    $item = $_
    $repo = $item.Repo
    $repoRoot = $using:root
    $rel = $repo
    if ($repoRoot -and $repo.StartsWith($repoRoot)) {
        $rel = $repo.Substring($repoRoot.Length).TrimStart('\', '/')
    }

    # status、branch、upstream差分、stashを1回の走査で取得する。
    $statusLines = @(& git -C $repo status --porcelain=v2 --branch --show-stash --ahead-behind --untracked-files=all 2>$null)
    $branch = '?'
    $staged = 0; $unstaged = 0; $untracked = 0; $stashed = 0; $ahead = 0; $behind = 0
    foreach ($line in $statusLines) {
        if ($line.StartsWith('# branch.head ')) {
            $branch = $line.Substring(14)
            if ($branch -eq '(detached)') { $branch = 'HEAD' }
        } elseif ($line -match '^# branch\.ab \+(\d+) -(\d+)$') {
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
        } elseif ($line -match '^# stash (\d+)$') {
            $stashed = [int]$Matches[1]
        } elseif ($line -match '^[12u] (..)' ) {
            $xy = $Matches[1]
            if ($xy[0] -ne '.') { $staged++ }
            if ($xy[1] -ne '.') { $unstaged++ }
        } elseif ($line.StartsWith('? ')) {
            $untracked++
        }
    }

    # リポジトリ属性は属性ごとではなく1回のGit呼び出しで取得する。
    $attrArgs = @(
        '-C', $repo, 'check-attr',
        'repo-main-branch', 'git-sweep-main', 'repo-protected-branches',
        'git-sweep-protected', 'repo-remote-only-branches', '--', '.'
    )
    $attrs = @{}
    foreach ($line in @(& git @attrArgs 2>$null)) {
        if ($line -match '^.*: ([^:]+): (.*)$') { $attrs[$Matches[1]] = $Matches[2] }
    }

    # fallback設定も1回で取得し、同じキーが複数あれば従来通り最後の値を使う。
    $configValues = @{}
    $legacyRemotePatterns = @()
    $configPattern = '^local\.(repo-main-branch|repo-protected-branches|repo-remote-only-branches|status-allowed-remote-branch|keep-up-to-date)$'
    foreach ($line in @(& git -C $repo config --get-regexp $configPattern 2>$null)) {
        if ($line -notmatch '^(\S+)\s(.*)$') { continue }
        if ($Matches[1] -eq 'local.status-allowed-remote-branch') {
            $legacyRemotePatterns += $Matches[2]
        } else {
            $configValues[$Matches[1]] = $Matches[2]
        }
    }

    # ローカル・originブランチとorigin/HEADを1回で取得する。
    $localBranchNames = @()
    $originBranchNames = @()
    $originHead = ''
    foreach ($line in @(& git -C $repo for-each-ref '--format=%(refname)%09%(symref)' refs/heads refs/remotes/origin 2>$null)) {
        $parts = @($line -split "`t", 2)
        $ref = $parts[0]
        $sym = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        if ($ref.StartsWith('refs/heads/')) {
            $localBranchNames += $ref.Substring(11)
        } elseif ($ref -eq 'refs/remotes/origin/HEAD') {
            if ($sym.StartsWith('refs/remotes/origin/')) { $originHead = $sym.Substring(20) }
        } elseif ($ref.StartsWith('refs/remotes/origin/')) {
            $originBranchNames += $ref.Substring(20)
        }
    }

    $mainBranch = $attrs['repo-main-branch']
    if (-not $mainBranch -or $mainBranch -eq 'unspecified') { $mainBranch = $attrs['git-sweep-main'] }
    if (-not $mainBranch -or $mainBranch -eq 'unspecified') { $mainBranch = $configValues['local.repo-main-branch'] }
    if (-not $mainBranch -and $originHead -and $originBranchNames -contains $originHead) { $mainBranch = $originHead }
    if (-not $mainBranch) { $mainBranch = 'main' }

    $protectedRaw = $attrs['repo-protected-branches']
    if (-not $protectedRaw -or $protectedRaw -eq 'unspecified') { $protectedRaw = $attrs['git-sweep-protected'] }
    if (-not $protectedRaw -or $protectedRaw -eq 'unspecified') { $protectedRaw = $configValues['local.repo-protected-branches'] }
    if ($protectedRaw -and $protectedRaw -ne 'unspecified') {
        $protectedList = @($protectedRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    } else {
        $protectedList = @($mainBranch)
        if ($mainBranch -ne 'main' -and ($localBranchNames -contains 'main' -or $originBranchNames -contains 'main')) {
            $protectedList += 'main'
        }
    }
    if ($protectedList -notcontains $mainBranch) { $protectedList += $mainBranch }

    $remoteOnlyRaw = $attrs['repo-remote-only-branches']
    if (-not $remoteOnlyRaw -or $remoteOnlyRaw -eq 'unspecified') { $remoteOnlyRaw = $configValues['local.repo-remote-only-branches'] }
    if ($remoteOnlyRaw -and $remoteOnlyRaw -ne 'unspecified') {
        $remoteOnlyList = @($remoteOnlyRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
        $legacyRemotePatterns = @()
    } else {
        $remoteOnlyList = @()
    }

    $base = $protectedList.Count
    $isProtected = $protectedList -contains $branch

    $statusParts = @()
    if ($staged -gt 0) { $statusParts += "+$staged" }
    if ($unstaged -gt 0) { $statusParts += "!$unstaged" }
    if ($untracked -gt 0) { $statusParts += "?$untracked" }
    if ($stashed -gt 0) { $statusParts += "*$stashed" }
    if ($ahead -gt 0) { $statusParts += "⇡$ahead" }
    if ($behind -gt 0) { $statusParts += "⇣$behind" }
    $statusStr = if ($statusParts.Count -gt 0) { $statusParts -join ' ' } else { '✓' }

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
    $baseExtra = $base - 1
    if ($baseExtra -gt 0) {
        $brStr = "1+$($localBr - 1)/1+$($originBr - 1)"
        $expectedBr = "1\+$baseExtra/1\+$($baseExtra + $remoteOnlyExpected)"
    } else {
        $brStr = "$localBr/$originBr"
        $expectedBr = "1/$($base + $remoteOnlyExpected)"
    }

    $charterVerFile = Join-Path $repo 'docs\dev-charter\VERSION'
    $charterVer = if (Test-Path -LiteralPath $charterVerFile) {
        [IO.File]::ReadAllText($charterVerFile).Trim()
    } else { '-' }
    if (-not $charterVer) { $charterVer = '-' }

    $keepVal = if ($configValues['local.keep-up-to-date'] -eq 'true') { 'keep' } else { 'skip' }

    $sepIdx = [Math]::Max($rel.LastIndexOf('\'), $rel.LastIndexOf('/'))
    if ($sepIdx -ge 0) {
        $groupName = $rel.Substring(0, $sepIdx)
        $repoName = $rel.Substring($sepIdx + 1)
    } else {
        $groupName = ''
        $repoName = $rel
    }

    [PSCustomObject]@{
        Index = $item.Index; Group = $groupName; RepoName = $repoName; Branch = $branch
        Status = $statusStr; Branches = $brStr; Charter = $charterVer; Keep = $keepVal
        ExpectedBranches = $expectedBr; IsProtected = $isProtected; PolicyOk = $policyOk
    }
} -ThrottleLimit $jobs | Sort-Object Index)

foreach ($data in $repoData) {
    $allGroups.Add($data.Group)
    $allRepoNames.Add($data.RepoName)
    $allBranches.Add($data.Branch)
    $allStatuses.Add($data.Status)
    $allBrs.Add($data.Branches)
    $allCharters.Add($data.Charter)
    $allKeeps.Add($data.Keep)
    $allBases.Add($data.ExpectedBranches)
    $allProtected.Add($data.IsProtected)
    $allPolicyOk.Add($data.PolicyOk)
    $allPaths.Add($repoList[$data.Index])
}

$activeIdxList = New-Object System.Collections.Generic.List[int]
for ($idx = 0; $idx -lt $allGroups.Count; $idx++) { $activeIdxList.Add($idx) }
$activeIdx = @($activeIdxList)
if (-not $SHOW_ALL -or $PATHS_ONLY) {
    $activeIdx = @($activeIdx | Where-Object {
        -not (Test-QuietRow $allProtected[$_] $allStatuses[$_] $allBrs[$_] $allBases[$_] $allPolicyOk[$_] $allCharters[$_] $charterLatest $IGNORE_CHARTER)
    })
}

if ($PATHS_ONLY) {
    foreach ($idx in $activeIdx) { Write-Host $allPaths[$idx] }
    exit 0
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
