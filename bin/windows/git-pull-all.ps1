#!/usr/bin/env pwsh
# git-pull-all: 1リポジトリの全ローカルブランチを upstream へ fast-forward 同期する
#
# 使い方:
#   git-pull-all [--fetch-only] [main-branch]
#
# オプション:
#   --fetch-only   fetch --all --prune だけ行い、ローカルブランチは更新しない
#   -h, --help     ヘルプを表示
#
# ブランチ方針（main / protected ブランチの解決順）は git-sweep と共通で、
# _git-branch-lib.ps1 の冒頭コメントに従う。
#
# 動作:
#   0. upstream という名前の remote があれば、fetch の前に `gh repo sync` で
#      upstream のデフォルトブランチを origin へ fast-forward 反映する
#      （diverge していれば警告のみ。gh 未インストール・未認証ならスキップ）
#   1. fetch --all --prune でリモートの更新・削除済みブランチを反映（失敗は終了コード1）
#   2. 現在のブランチを `pull --ff-only` で更新する。次の場合は更新せず warning を出す
#      - worktree が dirty（staged/unstaged/untracked）
#      - detached HEAD
#      - upstream が未設定（upstream がリモート側で削除済み（gone）のときは何も表示しない）
#      更新に失敗（分岐・コンフリクト）した場合は error を出して終了コード1にする
#   3. PROTECTED のうち現在のブランチ以外は、HEAD を動かさず fast-forward fetch で
#      同期する（コンフリクトがあれば警告のみ、自動マージはしない）。ローカルにまだ
#      無ければ origin から新規作成し、それが $MAIN なら checkout する
#      （develop 運用に気づかず main のまま作業を続ける事故を防ぐ。dirty なら切り替えない）
#   4. 現在のブランチ・PROTECTED 以外のローカルブランチも、upstream があれば
#      同様に HEAD を動かさず fast-forward fetch で同期する
#      （分岐していれば警告のみ。ローカルが先行していれば何もしない）
#
# 安全性の保証:
#   - 他の worktree で checkout 済みのブランチは更新・切り替えの対象にしない
#   - pull は fast-forward-only。暗黙の rebase や autostash は行わない
#   - 3・4 の fetch には --no-prune を付ける（fetch.prune=true の設定下では
#     `git fetch . <src>:<dst>` が失敗するため）。3・4 は作業ツリーを変更しないので
#     dirty でも実行する
#   - 成功メッセージ（Updated ...）は、対応する git コマンドが実際に成功し、
#     ブランチが進んだ場合のみ表示する

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

$FETCH_ONLY = $false
$MAIN_ARG = $null
$script:Failed = 0
$script:Dirty = $false

foreach ($arg in $args) {
    if ($arg -eq '--fetch-only') {
        $FETCH_ONLY = $true
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } elseif ($arg -like '-*') {
        Write-Stderr "error: unknown option: $arg"
        exit 1
    } else {
        $MAIN_ARG = $arg
    }
}

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Stderr "error: not a git repository"
    exit 1
}

Resolve-GitBranchPolicy
if ($MAIN_ARG) { $MAIN = $MAIN_ARG }
Add-GitBranchMainToProtected

Sync-GitForkUpstream (Get-Location).Path

$global:LASTEXITCODE = $null
& git fetch --all --prune --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Stderr "error: git fetch failed"
    exit 1
}

if ($FETCH_ONLY) { exit 0 }

if (@(& git status --porcelain 2>$null).Count -gt 0) {
    $script:Dirty = $true
}

# 現在のブランチを fast-forward pull する。HEAD が進んだ場合だけ Updated を表示する。
function Invoke-PullCurrent([string]$Current) {
    $before = (& git rev-parse HEAD).Trim()
    $global:LASTEXITCODE = $null
    & git pull --ff-only --quiet
    if ($LASTEXITCODE -eq 0) {
        $after = (& git rev-parse HEAD).Trim()
        if ($before -ne $after) { Write-Host "Updated $Current." }
    } else {
        Write-Stderr "error: could not fast-forward $Current (diverged or conflict). Resolve manually with 'git pull' or 'git merge'."
        $script:Failed = 1
    }
}

# ブランチ Branch を Up（リモート追跡ブランチ等）へ fast-forward する（HEAD は動かさない）。
# すでに最新・ローカルが先行している場合は何も表示しない。
# Protected の場合は、Up が無い旨も警告する。
function Sync-BranchFastForward([string]$Branch, [string]$Up, [bool]$IsProtected) {
    $global:LASTEXITCODE = $null
    & git rev-parse --verify -q $Up *> $null
    if ($LASTEXITCODE -ne 0) {
        if ($IsProtected) {
            Write-Stderr "warning: could not fast-forward $Branch ($Up not found). Run 'git checkout $Branch && git pull' manually."
        }
        return
    }
    $bRev = (& git rev-parse $Branch).Trim()
    $upRev = (& git rev-parse $Up).Trim()
    if ($bRev -eq $upRev) { return }
    $global:LASTEXITCODE = $null
    & git merge-base --is-ancestor $Branch $Up *> $null
    if ($LASTEXITCODE -ne 0) {
        # ローカルが先行しているだけなら何もしない。分岐していれば警告する
        $global:LASTEXITCODE = $null
        & git merge-base --is-ancestor $Up $Branch *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Stderr "warning: could not fast-forward $Branch (diverged). Run 'git checkout $Branch && git pull' manually."
        }
        return
    }
    if (Test-BranchInOtherWorktree $Branch) {
        Write-Host "Skipped: $Branch (checked out in another worktree; not updated)"
        return
    }
    $global:LASTEXITCODE = $null
    & git fetch --no-prune . "${Up}:refs/heads/${Branch}" --quiet *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Updated $Branch (fast-forward)."
    } else {
        Write-Stderr "warning: could not fast-forward $Branch. Run 'git checkout $Branch && git pull' manually."
    }
}

# PROTECTED のうち Current 以外を同期する。ローカルに既にあれば HEAD を動かさず
# fast-forward だけ行う。ローカルにまだ無ければ origin から新規作成し、それが
# $MAIN（develop 運用の統合ブランチ）であれば checkout する。
# 他の worktree で checkout 済みのブランチは更新・切り替えの対象にしない。
function Sync-OtherProtected([string]$Current) {
    foreach ($b in $PROTECTED) {
        if ($b -eq $Current) { continue }
        $global:LASTEXITCODE = $null
        & git rev-parse --verify -q $b *> $null
        if ($LASTEXITCODE -eq 0) {
            if (Test-BranchInOtherWorktree $b) {
                Write-Host "Skipped: $b (checked out in another worktree; not updated)"
                continue
            }
            Sync-BranchFastForward $b "origin/${b}" $true
        } else {
            $global:LASTEXITCODE = $null
            & git fetch --no-prune origin "${b}:${b}" --quiet *> $null
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

# 現在のブランチと PROTECTED 以外のローカルブランチを、upstream へ fast-forward
# 同期する。upstream 未設定・gone のブランチは何もしない。
function Sync-OtherBranches([string]$Current) {
    $refs = @(& git for-each-ref --format='%(refname:short)' refs/heads)
    foreach ($b in $refs) {
        if ($b -eq $Current) { continue }
        if (Test-Protected $b) { continue }
        $global:LASTEXITCODE = $null
        $up = (& git rev-parse --symbolic-full-name "${b}@{upstream}" 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $up) { continue }
        Sync-BranchFastForward $b $up $false
    }
}

$current = (& git rev-parse --abbrev-ref HEAD).Trim()

if ($current -eq 'HEAD') {
    Write-Stderr "warning: detached HEAD; skipping pull of the current checkout."
} elseif ($script:Dirty) {
    Write-Stderr "warning: worktree has uncommitted changes (staged, unstaged, or untracked); not pulling '$current'. Run 'git status' to review."
} else {
    $global:LASTEXITCODE = $null
    & git rev-parse --verify -q '@{upstream}' *> $null
    if ($LASTEXITCODE -eq 0) {
        Invoke-PullCurrent $current
    } else {
        $remote = (& git config --get "branch.${current}.remote" 2>$null)
        if (-not $remote) {
            Write-Stderr "warning: no upstream configured for '$current'; skipping pull."
        }
    }
}

Sync-OtherProtected $current
Sync-OtherBranches $current

exit $script:Failed
