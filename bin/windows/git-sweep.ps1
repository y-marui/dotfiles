#!/usr/bin/env pwsh
# git-sweep: マージ済みブランチを整理する
#
# 使い方:
#   git-sweep [--all] [main-branch]
#
# オプション:
#   --all   現在のブランチに加え、他のマージ済みブランチも削除する
#   -h, --help          ヘルプを表示
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
#   2. 現在の worktree が dirty（staged/unstaged/untracked）なら checkout・pull・
#      削除を一切行わずスキップし、理由を表示する
#   3. 現在のブランチが保護対象（PROTECTED）なら fast-forward pull するだけ
#   4. 現在のブランチがマージ済みなら $MAIN に切り替えて pull、ブランチ削除
#      （$MAIN が他の worktree で checkout 済みの場合は切り替えをスキップする）
#   5. PROTECTED のうち現在のブランチ以外は、HEAD を動かさず fast-forward fetch
#      で同期する（コンフリクトがあれば警告のみ、自動マージはしない）。ローカルに
#      まだ無ければ origin から新規作成し、それが $MAIN であれば checkout する
#   6. --all の場合、他のマージ済みブランチも削除
#   7. 保護ブランチ以外の残存ブランチを表示
#
# 安全性の保証:
#   - dirty な worktree（staged/unstaged/untracked のいずれか）は checkout・pull・
#     ブランチ削除の対象にしない
#   - 他の worktree で checkout 済みのブランチは切り替え・削除・fast-forward
#     更新の対象にしない（`git worktree list --porcelain` で明示的に検出する）
#   - pull は fast-forward-only。暗黙の rebase や autostash は行わず、
#     診断済みでコンフリクトの可能性がある操作は必ずユーザーの明示操作に委ねる
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
$script:MergeKind = $null
$script:Dirty = $false

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

if ($PROTECTED -notcontains $MAIN) { $PROTECTED += $MAIN }

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Stderr "error: not a git repository"
    exit 1
}

& git fetch --all --prune --quiet

$statusOutput = @(& git status --porcelain 2>$null)
if ($statusOutput.Count -gt 0) {
    $script:Dirty = $true
}

function Get-BranchNames {
    @(& git branch) | ForEach-Object { $_.TrimStart('*', '+', ' ') }
}

function Test-Protected([string]$Branch) {
    return $PROTECTED -contains $Branch
}

# ブランチ Branch が「現在の worktree 以外」で checkout されているパスを返す。
function Get-WorktreePathForBranch([string]$Branch) {
    $path = $null
    $branchName = $null
    $lines = @(& git worktree list --porcelain 2>$null) + @('')
    foreach ($line in $lines) {
        if ($line -like 'worktree *') {
            $path = $line.Substring(9)
        } elseif ($line -like 'branch *') {
            $branchName = $line -replace '^branch refs/heads/', ''
        } elseif ($line -eq '') {
            if ($path -and $branchName -eq $Branch) {
                return $path
            }
            $path = $null
            $branchName = $null
        }
    }
    return $null
}

function Test-BranchInOtherWorktree([string]$Branch) {
    $wt = Get-WorktreePathForBranch $Branch
    if (-not $wt) { return $false }
    $cur = (& git rev-parse --show-toplevel 2>$null)
    if (-not $cur) { $cur = (Get-Location).Path }
    return ($wt -ne $cur)
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

function Invoke-PullCurrent {
    $global:LASTEXITCODE = $null
    & git pull --ff-only --quiet
    if ($LASTEXITCODE -eq 0) {
        $cur = (& git rev-parse --abbrev-ref HEAD).Trim()
        Write-Host "Updated $cur."
    } else {
        $cur = (& git rev-parse --abbrev-ref HEAD).Trim()
        Write-Stderr "warning: could not fast-forward $cur (diverged or conflict). Resolve manually with 'git pull' or 'git merge'."
    }
}

function Sync-OtherProtected([string]$Current) {
    foreach ($b in $PROTECTED) {
        if ($b -eq $Current) { continue }
        & git rev-parse --verify -q $b *> $null
        if ($LASTEXITCODE -eq 0) {
            if (Test-BranchInOtherWorktree $b) {
                Write-Host "Skipped: $b (checked out in another worktree; not updated)"
                continue
            }
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
                    if ($script:Dirty) {
                        Write-Stderr "warning: worktree has uncommitted changes; not switching to $MAIN. Run 'git checkout $MAIN' after committing/stashing."
                    } elseif (Test-BranchInOtherWorktree $MAIN) {
                        Write-Stderr "warning: $MAIN is checked out in another worktree; not switching."
                    } else {
                        $global:LASTEXITCODE = $null
                        & git checkout $MAIN *> $null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Switched to $MAIN."
                        } else {
                            Write-Stderr "warning: failed to checkout $MAIN."
                        }
                    }
                }
            }
        }
    }
}

$current = (& git rev-parse --abbrev-ref HEAD).Trim()

if ($script:Dirty) {
    Write-Stderr "warning: worktree has uncommitted changes (staged, unstaged, or untracked); skipping checkout/pull/delete for '$current'. Run 'git status' to review."
    if (Test-Protected $current) {
        Sync-OtherProtected $current
    }
} elseif (Test-Protected $current) {
    Invoke-PullCurrent
    Sync-OtherProtected $current
} elseif (Test-Merged $current) {
    $kind = $script:MergeKind
    if (Test-BranchInOtherWorktree $MAIN) {
        Write-Stderr "warning: '$MAIN' is checked out in another worktree; skipping switch/cleanup for '$current'."
    } else {
        Write-Host "Branch '$current' is merged. Switching to $MAIN..."
        $global:LASTEXITCODE = $null
        & git checkout $MAIN *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-PullCurrent
            Remove-Branch $current $kind
        } else {
            Write-Stderr "warning: failed to checkout $MAIN; leaving '$current' in place."
        }
    }
    Sync-OtherProtected $MAIN
} else {
    Write-Host "Branch '$current' is not yet merged into $MAIN."
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
