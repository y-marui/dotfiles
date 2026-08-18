#!/usr/bin/env pwsh
# git-sweep: マージ済みブランチを整理する
#
# 使い方:
#   git-sweep [--all] [main-branch]
#
# オプション:
#   --all   現在のブランチに加え、他のマージ済みブランチも削除する
#
# 動作:
#   1. fetch --prune でリモートの削除済みブランチを反映
#   2. 現在のブランチがマージ済みなら main に切り替えて pull、ブランチ削除
#   3. --all の場合、他のマージ済みブランチも削除
#   4. main 以外の残存ブランチを表示
#
# マージ済みの判定:
#   - git branch --merged（fast-forward / merge commit）
#   - リモートブランチが gone（squash merge / rebase merge 後に PR がクローズ済み）

Set-StrictMode -Version Latest

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

$ALL = $false
$MAIN = 'main'

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

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Stderr "error: not a git repository"
    exit 1
}

& git fetch --all --prune --quiet

function Get-BranchNames {
    @(& git branch) | ForEach-Object { $_.TrimStart('*', ' ') }
}

function Test-Merged([string]$Branch) {
    $global:LASTEXITCODE = $null
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

function Invoke-PullMain {
    $global:LASTEXITCODE = $null
    & git pull --rebase --autostash --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Updated $MAIN."
    } else {
        & git rebase --abort *> $null
        Write-Stderr "warning: could not pull $MAIN (conflict). Run 'git pull --rebase' manually."
    }
}

$current = (& git rev-parse --abbrev-ref HEAD).Trim()

if ($current -eq $MAIN) {
    Invoke-PullMain
} elseif (Test-Merged $current) {
    Write-Host "Branch '$current' is merged. Switching to $MAIN..."
    & git checkout $MAIN | Out-Null
    Invoke-PullMain
    Remove-Branch $current
    Write-Host "Deleted: $current"
} else {
    Write-Host "Branch '$current' is not yet merged into $MAIN."
}

if ($ALL) {
    foreach ($b in (Get-BranchNames)) {
        if ($b -eq $MAIN) { continue }
        if (Test-Merged $b) {
            Remove-Branch $b
            Write-Host "Deleted: $b"
        }
    }
}

$others = @(Get-BranchNames | Where-Object { $_ -ne $MAIN })

if ($others.Count -gt 0) {
    Write-Host ""
    Write-Host "Remaining branches:"
    foreach ($b in $others) {
        Write-Host "  $b"
    }
}
