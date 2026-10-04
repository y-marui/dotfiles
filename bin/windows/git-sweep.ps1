#!/usr/bin/env pwsh
# git-sweep: マージ済みブランチを整理する
#
# 使い方:
#   git-sweep [--all] [--no-pull] [main-branch]
#
# オプション:
#   --all       現在のブランチに加え、他のマージ済みブランチも削除する
#   --no-pull   ローカルブランチの fast-forward 更新（pull・同期）を行わない
#               （fetch --prune とマージ済みブランチの削除は行う）
#   -h, --help          ヘルプを表示
#
# ブランチ方針（main / protected ブランチの解決順）は git-pull-all と共通で、
# _git-branch-lib.ps1 の冒頭コメントに従う。
#
# 動作:
#   1. --no-pull でなければ git-pull-all を実行する（fork の upstream 同期、
#      fetch --all --prune、現在ブランチ・PROTECTED・その他ローカルブランチの
#      fast-forward 同期。詳細は git-pull-all を参照）。git-pull-all が失敗
#      （fetch 失敗・現在ブランチの pull 失敗）しても続行し、最後に終了コード1にする。
#      --no-pull の場合は fork の upstream 同期と fetch --prune だけ行う
#   2. 現在の worktree が dirty（staged/unstaged/untracked）なら checkout・削除を
#      行わずスキップし、理由を表示する
#   3. 現在のブランチが保護対象（PROTECTED）なら何もしない
#   4. 現在のブランチがマージ済みなら $MAIN に切り替えてブランチ削除
#      （$MAIN が他の worktree で checkout 済みの場合は切り替えをスキップする）
#   5. --all の場合、他のマージ済みブランチも削除
#   6. 保護ブランチ以外の残存ブランチを表示
#
# 安全性の保証:
#   - dirty な worktree（staged/unstaged/untracked のいずれか）の現在ブランチは
#     checkout・pull・削除の対象にしない
#   - 他の worktree で checkout 済みのブランチは切り替え・削除・fast-forward
#     更新の対象にしない（`git worktree list --porcelain` で明示的に検出する）
#   - pull は fast-forward-only（git-pull-all）。暗黙の rebase や autostash は行わず、
#     コンフリクトの可能性がある操作は必ずユーザーの明示操作に委ねる
#   - `git branch -d` の失敗を理由なく `-D` にフォールバックしない。squash/rebase
#     merge 後の `gone` 判定は、squash された変更が $MAIN 側に実在することを
#     git-delete-squashed 相当のアルゴリズムで検証してからのみ `-D` を使う
#   - 削除・fast-forward の成功メッセージは、対応する git コマンドが実際に
#     成功した場合のみ表示する
#
# マージ済みの判定:
#   - PROTECTED に含まれるブランチは常に対象外
#   - $MAIN と同一コミット（まだ何もコミットしていない新規ブランチ）も対象外
#     （誤削除防止: 作成直後は HEAD が $MAIN と同じコミットを指すため、
#     git branch --merged だけで判定すると常に「マージ済み」扱いになってしまう）
#   - git branch --merged（fast-forward / merge commit）
#   - リモートブランチが gone、かつ merge-base からの差分が $MAIN 側の履歴に
#     実在する（squash/rebase merge 後の内容が確認できる。追加のローカル専用
#     コミットがある場合は不一致になり対象外のまま残る）

Set-StrictMode -Version Latest

. "$PSScriptRoot\_git-fork-lib.ps1"
. "$PSScriptRoot\_git-branch-lib.ps1"

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

$ALL = $false
$NO_PULL = $false
$script:MergeKind = $null
$script:Dirty = $false

Resolve-GitBranchPolicy

foreach ($arg in $args) {
    if ($arg -eq '--all') {
        $ALL = $true
    } elseif ($arg -eq '--no-pull') {
        $NO_PULL = $true
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } elseif ($arg -like '-*') {
        Write-Stderr "error: unknown option: $arg"
        exit 1
    } else {
        $MAIN = $arg
    }
}

Add-GitBranchMainToProtected

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Stderr "error: not a git repository"
    exit 1
}

# ローカルブランチの更新（pull・同期）は git-pull-all に任せる。--no-pull の場合は
# 更新せず、fork の upstream 同期と fetch --prune だけ行う（マージ済み判定に必要）。
$pullFailed = $false
if ($NO_PULL) {
    Sync-GitForkUpstream (Get-Location).Path
    $global:LASTEXITCODE = $null
    & git fetch --all --prune --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Stderr "error: git fetch failed"
        exit 1
    }
} else {
    $global:LASTEXITCODE = $null
    & "$PSScriptRoot\git-pull-all.ps1" $MAIN
    if ($LASTEXITCODE -ne 0) { $pullFailed = $true }
}

$statusOutput = @(& git status --porcelain 2>$null)
if ($statusOutput.Count -gt 0) {
    $script:Dirty = $true
}

function Get-BranchNames {
    @(& git branch) | ForEach-Object { $_.TrimStart('*', '+', ' ') }
}

# squash/rebase merge で $MAIN に取り込まれた内容が、ブランチ Branch の
# merge-base 以降の差分と一致するかを検証する（git-delete-squashed 相当）。
function Test-SquashIntegrated([string]$Branch) {
    $global:LASTEXITCODE = $null
    $mergeBase = (& git merge-base $MAIN $Branch 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $mergeBase) { return $false }

    $global:LASTEXITCODE = $null
    $tree = (& git rev-parse "${Branch}^{tree}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $tree) { return $false }

    # merge-base 以降に変更が全く無ければ、失うものは無いので安全とみなす。
    & git diff --quiet $mergeBase $Branch -- 2>$null
    if ($LASTEXITCODE -eq 0) { return $true }

    $global:LASTEXITCODE = $null
    $synth = (& git commit-tree $tree -p $mergeBase -m _git-sweep-squash-check 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $synth) { return $false }

    $global:LASTEXITCODE = $null
    $mark = @(& git cherry $MAIN $synth 2>$null)
    if ($LASTEXITCODE -ne 0) { return $false }
    if ($mark.Count -eq 0) { return $false }
    return ($mark[0] -like '-*')
}

# ブランチがマージ済みか判定する。真を返す場合は $script:MergeKind に
# "ff"（fast-forward/merge commit）または "squash"（squash/rebase merge、
# 内容の一致を検証済み）を設定する。
function Test-Merged([string]$Branch) {
    $script:MergeKind = $null
    if (Test-Protected $Branch) { return $false }

    $global:LASTEXITCODE = $null
    $branchRev = (& git rev-parse $Branch 2>$null)
    $mainRev = (& git rev-parse $MAIN 2>$null)
    if ($branchRev -and $mainRev -and $branchRev -eq $mainRev) { return $false }

    $merged = @(& git branch --merged $MAIN 2>$null) | ForEach-Object { $_.TrimStart('*', '+', ' ') }
    if ($merged -contains $Branch) {
        $script:MergeKind = 'ff'
        return $true
    }

    $vv = @(& git branch -vv)
    $isGone = $false
    foreach ($line in $vv) {
        if ($line -match "^[*+]?\s+$([regex]::Escape($Branch))\s+[0-9a-f]+\s+\[.*: gone\]") {
            $isGone = $true
            break
        }
    }
    if ($isGone -and (Test-SquashIntegrated $Branch)) {
        $script:MergeKind = 'squash'
        return $true
    }
    return $false
}

# 検証済みの判定結果 (Kind) に基づいてのみ削除する。理由のない -d から -D への
# フォールバックは行わない。成功メッセージは実際の削除成功時のみ表示する。
function Remove-Branch([string]$Branch, [string]$Kind) {
    if ($Kind -eq 'squash') {
        $global:LASTEXITCODE = $null
        & git branch -D $Branch *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Deleted: $Branch (squash/rebase merge, verified)"
        } else {
            Write-Stderr "warning: failed to delete $Branch"
        }
    } else {
        $global:LASTEXITCODE = $null
        & git branch -d $Branch *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Deleted: $Branch"
        } else {
            Write-Stderr "warning: failed to delete $Branch (not fully merged into $MAIN; skipping)"
        }
    }
}

$current = (& git rev-parse --abbrev-ref HEAD).Trim()

if ($script:Dirty) {
    Write-Stderr "warning: worktree has uncommitted changes (staged, unstaged, or untracked); skipping checkout/delete for '$current'. Run 'git status' to review."
} elseif (Test-Protected $current) {
    # 保護対象のブランチは何もしない
} else {
    if (Test-Merged $current) {
        $kind = $script:MergeKind
        if (Test-BranchInOtherWorktree $MAIN) {
            Write-Stderr "warning: '$MAIN' is checked out in another worktree; skipping switch/cleanup for '$current'."
        } else {
            Write-Host "Branch '$current' is merged. Switching to $MAIN..."
            $global:LASTEXITCODE = $null
            & git checkout $MAIN *> $null
            if ($LASTEXITCODE -eq 0) {
                Remove-Branch $current $kind
            } else {
                Write-Stderr "warning: failed to checkout $MAIN; leaving '$current' in place."
            }
        }
    } else {
        Write-Host "Branch '$current' is not yet merged into $MAIN."
    }
}

if ($ALL) {
    $current2 = (& git rev-parse --abbrev-ref HEAD).Trim()
    foreach ($b in (Get-BranchNames)) {
        if (Test-Protected $b) { continue }
        if ($b -eq $current2) { continue }
        if (Test-BranchInOtherWorktree $b) {
            Write-Host "Skipped: $b (checked out in another worktree)"
            continue
        }
        if (Test-Merged $b) {
            Remove-Branch $b $script:MergeKind
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

if ($pullFailed) { exit 1 }
