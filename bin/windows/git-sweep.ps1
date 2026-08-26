#!/usr/bin/env pwsh
# git-sweep: マージ済みブランチを整理する
#
# 使い方:
#   git-sweep [--all] [main-branch]
#
# オプション:
#   --all   現在のブランチに加え、他のマージ済みブランチも削除する
#
# リポジトリのブランチ方針は .gitattributes に宣言する:
#   * repo-main-branch=develop
#   * repo-protected-branches=main,develop
# 優先順位は、コマンドライン引数 [main-branch]、上記属性、ローカルGit config
# (local.repo-main-branch / local.repo-protected-branches)、origin/HEAD、main。
# 旧 git-sweep-main / git-sweep-protected 属性も互換fallbackとして読み取る。
#
# 動作:
#   1. fetch --prune でリモートの削除済みブランチを反映
#   2. 現在のブランチが保護対象（PROTECTED）なら pull するだけ
#   3. 現在のブランチがマージ済みなら $MAIN に切り替えて pull、ブランチ削除
#   4. PROTECTED のうち現在のブランチ以外は、HEAD を動かさず fast-forward fetch
#      で同期する（コンフリクトがあれば警告のみ、自動マージはしない）
#   5. --all の場合、他のマージ済みブランチも削除
#   6. 保護ブランチ以外の残存ブランチを表示
#
# マージ済みの判定:
#   - PROTECTED に含まれるブランチは常に対象外
#   - $MAIN と同一コミット（まだ何もコミットしていない新規ブランチ）も対象外
#     （誤削除防止: 作成直後は HEAD が $MAIN と同じコミットを指すため、
#     git branch --merged だけで判定すると常に「マージ済み」扱いになってしまう）
#   - git branch --merged（fast-forward / merge commit）
#   - リモートブランチが gone（squash merge / rebase merge 後に PR がクローズ済み）

Set-StrictMode -Version Latest

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Get-Attr([string]$Attr) {
    $global:LASTEXITCODE = $null
    $output = & git check-attr $Attr -- . 2>$null
    if ($output -match ": ${Attr}: (.+)$") {
        return $Matches[1]
    }
    return $null
}

function Get-ConfigValue([string]$Key) {
    $global:LASTEXITCODE = $null
    $value = (& git config --get $Key 2>$null)
    if ($LASTEXITCODE -eq 0 -and $value) { return $value.Trim() }
    return $null
}

function ConvertFrom-BranchCsv([string]$Csv) {
    if (-not $Csv) { return @() }
    return @($Csv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
}

$ALL = $false
$MAIN = $null
$PROTECTED = @()

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -eq 0) {
    $attrMain = Get-Attr 'repo-main-branch'
    if (-not $attrMain -or $attrMain -eq 'unspecified') {
        $attrMain = Get-Attr 'git-sweep-main'
    }
    if ($attrMain -and $attrMain -ne 'unspecified') {
        $MAIN = $attrMain
    } else {
        $MAIN = Get-ConfigValue 'local.repo-main-branch'
    }
    if (-not $MAIN) {
        $originHead = (& git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $originHead) {
            $originHead = $originHead -replace '^origin/', ''
            & git show-ref --verify --quiet "refs/remotes/origin/$originHead"
            if ($LASTEXITCODE -eq 0) { $MAIN = $originHead }
        }
    }

    $attrProtected = Get-Attr 'repo-protected-branches'
    if (-not $attrProtected -or $attrProtected -eq 'unspecified') {
        $attrProtected = Get-Attr 'git-sweep-protected'
    }
    if ($attrProtected -and $attrProtected -ne 'unspecified') {
        $PROTECTED = @(ConvertFrom-BranchCsv $attrProtected)
    } else {
        $configProtected = Get-ConfigValue 'local.repo-protected-branches'
        if ($configProtected) { $PROTECTED = @(ConvertFrom-BranchCsv $configProtected) }
    }
}

if (-not $MAIN) { $MAIN = 'main' }
if ($PROTECTED.Count -eq 0) {
    $PROTECTED = @($MAIN)
    if ($MAIN -ne 'main') {
        & git show-ref --verify --quiet refs/heads/main
        $hasMain = ($LASTEXITCODE -eq 0)
        if (-not $hasMain) {
            & git show-ref --verify --quiet refs/remotes/origin/main
            $hasMain = ($LASTEXITCODE -eq 0)
        }
        if ($hasMain) { $PROTECTED += 'main' }
    }
}

foreach ($arg in $args) {
    if ($arg -eq '--all') {
        $ALL = $true
    } elseif ($arg -like '-*') {
        Write-Stderr "error: unknown option: $arg"
        exit 1
    } else {
        $MAIN = $arg
    }
}

if ($PROTECTED -notcontains $MAIN) { $PROTECTED += $MAIN }

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Stderr "error: not a git repository"
    exit 1
}

& git fetch --all --prune --quiet

function Get-BranchNames {
    @(& git branch) | ForEach-Object { $_.TrimStart('*', ' ') }
}

function Test-Protected([string]$Branch) {
    return $PROTECTED -contains $Branch
}

function Test-Merged([string]$Branch) {
    if (Test-Protected $Branch) { return $false }

    $global:LASTEXITCODE = $null
    $branchRev = (& git rev-parse $Branch 2>$null)
    $mainRev = (& git rev-parse $MAIN 2>$null)
    if ($branchRev -and $mainRev -and $branchRev -eq $mainRev) { return $false }

    $merged = @(& git branch --merged $MAIN 2>$null) | ForEach-Object { $_.TrimStart('*', ' ') }
    if ($merged -contains $Branch) { return $true }

    $vv = @(& git branch -vv)
    foreach ($line in $vv) {
        if ($line -match "^[*]?\s+$([regex]::Escape($Branch))\s+[0-9a-f]+\s+\[.*: gone\]") {
            return $true
        }
    }
    return $false
}

function Remove-Branch([string]$Branch) {
    & git branch -d $Branch *> $null
    if ($LASTEXITCODE -ne 0) {
        & git branch -D $Branch | Out-Null
    }
}

function Invoke-PullCurrent {
    $global:LASTEXITCODE = $null
    & git pull --rebase --autostash --quiet
    if ($LASTEXITCODE -eq 0) {
        $cur = (& git rev-parse --abbrev-ref HEAD).Trim()
        Write-Host "Updated $cur."
    } else {
        & git rebase --abort *> $null
        Write-Stderr "warning: could not pull (conflict). Run 'git pull --rebase' manually."
    }
}

function Sync-OtherProtected([string]$Current) {
    foreach ($b in $PROTECTED) {
        if ($b -eq $Current) { continue }
        & git rev-parse --verify -q $b *> $null
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = $null
            & git fetch . "origin/${b}:${b}" --quiet *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Updated $b (fast-forward)."
            } else {
                Write-Stderr "warning: could not fast-forward $b. Run 'git checkout $b && git pull' manually."
            }
        } else {
            $global:LASTEXITCODE = $null
            & git fetch origin "${b}:${b}" --quiet *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Created local branch $b (tracking origin/$b)."
                if ($b -eq $MAIN) {
                    & git checkout $MAIN | Out-Null
                    Write-Host "Switched to $MAIN."
                }
            }
        }
    }
}

$current = (& git rev-parse --abbrev-ref HEAD).Trim()

if (Test-Protected $current) {
    Invoke-PullCurrent
    Sync-OtherProtected $current
} elseif (Test-Merged $current) {
    Write-Host "Branch '$current' is merged. Switching to $MAIN..."
    & git checkout $MAIN | Out-Null
    Invoke-PullCurrent
    Remove-Branch $current
    Write-Host "Deleted: $current"
    Sync-OtherProtected $MAIN
} else {
    Write-Host "Branch '$current' is not yet merged into $MAIN."
}

if ($ALL) {
    foreach ($b in (Get-BranchNames)) {
        if (Test-Protected $b) { continue }
        if (Test-Merged $b) {
            Remove-Branch $b
            Write-Host "Deleted: $b"
        }
    }
}

$others = @(Get-BranchNames | Where-Object { -not (Test-Protected $_) })

if ($others.Count -gt 0) {
    Write-Host ""
    Write-Host "Remaining branches:"
    foreach ($b in $others) {
        Write-Host "  $b"
    }
}
