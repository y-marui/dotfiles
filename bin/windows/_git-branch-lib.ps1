# bin/windows/_git-branch-lib.ps1
# git-sweep.ps1・git-pull-all.ps1 から dot-source される、ブランチ方針の解決と
# worktree 判定の共通関数（bin/unix/_git-branch-lib.sh と対応する）。
#
# リポジトリのブランチ方針は .gitattributes に宣言する:
#   * repo-main-branch=develop
#   * repo-protected-branches=main,develop
# 優先順位は、コマンドライン引数 [main-branch]、上記属性、ローカルGit config
# (local.repo-main-branch / local.repo-protected-branches)、origin/HEAD、main。
# 旧 git-sweep-main / git-sweep-protected 属性も互換fallbackとして読み取る。
#
# 呼び出し側は Resolve-GitBranchPolicy を呼んだあと、引数で main-branch を
# 受け取った場合は $MAIN を上書きしてから Add-GitBranchMainToProtected を呼ぶ。
# 結果は呼び出し側のスクリプトスコープの $MAIN と $PROTECTED に入る。

$script:MAIN = $null
$script:PROTECTED = @()

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

# Resolve-GitBranchPolicy: カレントのリポジトリから $MAIN と $PROTECTED を解決する。
function Resolve-GitBranchPolicy {
    & git rev-parse --git-dir *> $null
    if ($LASTEXITCODE -eq 0) {
        $attrMain = Get-Attr 'repo-main-branch'
        if (-not $attrMain -or $attrMain -eq 'unspecified') {
            $attrMain = Get-Attr 'git-sweep-main'
        }
        if ($attrMain -and $attrMain -ne 'unspecified') {
            $script:MAIN = $attrMain
        } else {
            $script:MAIN = Get-ConfigValue 'local.repo-main-branch'
        }
        if (-not $script:MAIN) {
            $originHead = (& git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null)
            if ($LASTEXITCODE -eq 0 -and $originHead) {
                $originHead = $originHead -replace '^origin/', ''
                & git show-ref --verify --quiet "refs/remotes/origin/$originHead"
                if ($LASTEXITCODE -eq 0) { $script:MAIN = $originHead }
            }
        }

        $attrProtected = Get-Attr 'repo-protected-branches'
        if (-not $attrProtected -or $attrProtected -eq 'unspecified') {
            $attrProtected = Get-Attr 'git-sweep-protected'
        }
        if ($attrProtected -and $attrProtected -ne 'unspecified') {
            $script:PROTECTED = @(ConvertFrom-BranchCsv $attrProtected)
        } else {
            $configProtected = Get-ConfigValue 'local.repo-protected-branches'
            if ($configProtected) { $script:PROTECTED = @(ConvertFrom-BranchCsv $configProtected) }
        }
    }

    if (-not $script:MAIN) { $script:MAIN = 'main' }
    if ($script:PROTECTED.Count -eq 0) {
        $script:PROTECTED = @($script:MAIN)
        if ($script:MAIN -ne 'main') {
            & git show-ref --verify --quiet refs/heads/main
            $hasMain = ($LASTEXITCODE -eq 0)
            if (-not $hasMain) {
                & git show-ref --verify --quiet refs/remotes/origin/main
                $hasMain = ($LASTEXITCODE -eq 0)
            }
            if ($hasMain) { $script:PROTECTED += 'main' }
        }
    }
}

function Add-GitBranchMainToProtected {
    if ($script:PROTECTED -notcontains $script:MAIN) { $script:PROTECTED += $script:MAIN }
}

function Test-Protected([string]$Branch) {
    return $script:PROTECTED -contains $Branch
}

# ブランチ Branch が checkout されている worktree のパスを返す（無ければ $null）。
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

# ブランチ Branch が「現在の worktree 以外」で checkout されているかを判定する。
function Test-BranchInOtherWorktree([string]$Branch) {
    $wt = Get-WorktreePathForBranch $Branch
    if (-not $wt) { return $false }
    $cur = (& git rev-parse --show-toplevel 2>$null)
    if (-not $cur) { $cur = (Get-Location).Path }
    return ($wt -ne $cur)
}
