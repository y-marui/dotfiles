# bin/_ghq-lib.ps1
# ghq-pull.ps1 / ghq-update.ps1 から dot source される共通関数。
# macOS/RPi の bin/_ghq-lib.sh に相当。
#
# uv.lock・package-lock.json はローカルの `uv sync`/`npm update` 等で
# 頻繁に更新され、コミットされていない差分を抱えやすい。これだけを理由に
# dirty working tree として処理全体をスキップしてしまうと ghq-pull /
# ghq-update が実質的に動かなくなるため、これらロックファイルのみが dirty
# な場合は一時的に stash して処理を継続し、処理後に復元する。ロックファイル
# 以外にも dirty な変更がある場合は従来通りスキップする。

Set-StrictMode -Version Latest

function Write-GhqStderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

$Script:GhqPriorityRepos = @('dotfiles', 'dev-charter')

# Get-GhqOrderedList <filter>
# ghq list -p の結果を、$Script:GhqPriorityRepos に列挙したリポジトリ（存在し filter に
# 一致するもののみ）を先頭に、残りをソートした順で返す。
# dotfiles はツール自体（ghq-update.ps1 等のスクリプト）を、dev-charter は各リポジトリの
# 基準バージョン（docs/dev-charter/VERSION の比較元）を提供するため、他のリポジトリ
# より先に最新化しておきたい。
function Get-GhqOrderedList([string]$Filter) {
    $all = @(& ghq list -p)
    if ($Filter) {
        # owner/repo 記法（"/"区切り）でフィルタを書けるよう、Windowsのバックスラッシュ
        # パスを比較用に正規化する（実際のファイル操作には元のパスを使う）
        $all = @($all | Where-Object { ($_ -replace '\\', '/') -match $Filter })
    }
    if ($all.Count -eq 0) { return @() }

    $rest = [System.Collections.ArrayList]@($all)
    $ordered = [System.Collections.ArrayList]@()

    foreach ($name in $Script:GhqPriorityRepos) {
        $match = $rest | Where-Object { ($_ -replace '\\', '/') -match "/${name}`$" } | Select-Object -First 1
        if ($match) {
            [void]$ordered.Add($match)
            [void]$rest.Remove($match)
        }
    }

    [void]$ordered.AddRange(@($rest | Sort-Object))
    return $ordered
}

$Script:GhqStashed = $false
$Script:GhqLockfiles = @('uv.lock', 'package-lock.json')

# Push-GhqLockfileStash <repo>
# 戻り値 $true : 処理続行可（clean、または $Script:GhqLockfiles のみ dirty で stash 済み）
# 戻り値 $false: $Script:GhqLockfiles 以外にも dirty な変更があるためスキップすべき
function Push-GhqLockfileStash([string]$Repo) {
    $Script:GhqStashed = $false
    $porcelain = @(& git -C $Repo status --porcelain 2>$null)
    if (-not $porcelain) { return $true }

    $other = $porcelain
    foreach ($f in $Script:GhqLockfiles) {
        $escaped = [regex]::Escape($f)
        $other = @($other | Where-Object { $_ -notmatch " $escaped$" })
    }
    if ($other.Count -gt 0) { return $false }

    $dirty = @()
    foreach ($f in $Script:GhqLockfiles) {
        $escaped = [regex]::Escape($f)
        if (@($porcelain | Where-Object { $_ -match " $escaped$" }).Count -gt 0) { $dirty += $f }
    }
    if ($dirty.Count -eq 0) { return $true }

    $global:LASTEXITCODE = $null
    & git -C $Repo stash push --include-untracked --quiet --message 'ghq-lib: lockfiles' -- @dirty
    if ($LASTEXITCODE -ne 0) { return $false }
    $Script:GhqStashed = $true
    return $true
}

# Pop-GhqLockfileStash <repo>
# Push-GhqLockfileStash で stash したロックファイルを復元する。
# pull 等でリモート側も同じファイルを更新していた場合はコンフリクトしうるため、
# その場合は stash を残したまま失敗を報告する（自動では解決しない）。
function Pop-GhqLockfileStash([string]$Repo) {
    if (-not $Script:GhqStashed) { return $true }

    $global:LASTEXITCODE = $null
    & git -C $Repo stash pop --quiet
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-GhqStderr "  [conflict] ロックファイルの復元に失敗（手動で解決してください: cd ${Repo} && git stash list）"
    return $false
}

# Invoke-GhqAutoPrLockfile <repo> <base_branch> <lockfile> <branch> <title> <body>
# uv sync --upgrade / npm update により <lockfile> のみが dirty な場合、
# <branch> にコミットして force push し、gh で PR を作成する（既に open な
# PR があれば push だけでその PR に反映される）。作業ツリーは base_branch
# に戻した状態で返す。失敗時も呼び出し元の処理は継続できるよう例外は投げない。
function Invoke-GhqAutoPrLockfile([string]$Repo, [string]$BaseBranch, [string]$Lockfile, [string]$Branch, [string]$Title, [string]$Body) {
    $branch = $Branch
    $escapedLockfile = [regex]::Escape($Lockfile)

    $lockStatus = @(& git -C $Repo status --porcelain -- $Lockfile 2>$null)
    if (-not $lockStatus) { return }

    $allStatus = @(& git -C $Repo status --porcelain 2>$null)
    $other = @($allStatus | Where-Object { $_ -notmatch " $escapedLockfile$" })
    if ($other.Count -gt 0) {
        Write-GhqStderr "  [skip auto-pr] (${Repo}) ${Lockfile} 以外にも dirty な変更があります"
        return
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-GhqStderr "  [skip auto-pr] (${Repo}) 'gh' が見つかりません（${Lockfile} の変更はローカルに残しています）"
        return
    }

    Push-Location $Repo
    try {
        $global:LASTEXITCODE = $null
        & gh auth status *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-GhqStderr "  [skip auto-pr] (${Repo}) gh が未認証です（${Lockfile} の変更はローカルに残しています）"
            return
        }
    } finally {
        Pop-Location
    }

    # origin の remote URL から owner/repo を直接切り出す。upstream 等の追加
    # remote がある fork で --repo を渡さずに gh pr list/create を実行すると、
    # gh がベースリポジトリを fork 元だと誤解決し、origin にしか存在しない
    # ブランチが見つからず PR 作成が常に失敗する。gh repo view による解決は
    # ~/.ssh/config の Host エイリアス（github-public:owner/repo.git 等）を
    # 解釈できないため使わず、正規表現で owner/repo を抜き出す。
    $originUrl = (& git -C $Repo remote get-url origin 2>$null)
    $ghRepo = $null
    if ($originUrl) {
        $trimmed = $originUrl -replace '\.git$', ''
        if ($trimmed -match '[:/]([^/]+/[^/]+)$') {
            $ghRepo = $Matches[1]
        }
    }
    if (-not $ghRepo) {
        Write-GhqStderr "  [skip auto-pr] (${Repo}) origin リポジトリを解決できませんでした"
        return
    }

    $global:LASTEXITCODE = $null
    & git -C $Repo checkout -B $branch *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-GhqStderr "  [skip auto-pr] (${Repo}) ブランチ作成に失敗しました"
        return
    }
    $global:LASTEXITCODE = $null
    $commitOutput = (& git -C $Repo commit -m $Title -- $Lockfile 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        $commitSummary = ($commitOutput -replace "`r?`n", ' ').Trim()
        if ($commitSummary.Length -gt 500) { $commitSummary = $commitSummary.Substring(0, 500) }
        Write-GhqStderr "  [skip auto-pr] (${Repo}) commit に失敗しました: ${commitSummary}"
        & git -C $Repo checkout $BaseBranch *> $null
        return
    }
    $global:LASTEXITCODE = $null
    & git -C $Repo push --force-with-lease -u origin $branch *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-GhqStderr "  [warn] push に失敗しました（ローカルブランチ '${branch}' に残しています: ${Repo}）"
        & git -C $Repo checkout $BaseBranch *> $null
        return
    }

    Push-Location $Repo
    try {
        $prCountRaw = & gh pr list --repo $ghRepo --head $branch --state open --json number -q 'length' 2>$null
        $prCount = if ($prCountRaw) { $prCountRaw } else { '0' }
        if ($prCount -eq '0') {
            $prCreateArgs = @(
                '--repo', $ghRepo,
                '--title', $Title,
                '--body', $Body,
                '--base', $BaseBranch,
                '--head', $branch
            )
            # 自分（y-marui）名義のリポジトリでは見逃し防止のため自分を assignee にする
            if ($ghRepo -like 'y-marui/*') {
                $prCreateArgs += @('--assignee', 'y-marui')
            }
            $global:LASTEXITCODE = $null
            $createErr = & gh pr create @prCreateArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [auto-pr] PR を作成しました: ${branch}"
            } else {
                Write-GhqStderr "  [warn] PR 作成に失敗しました（ブランチは push 済み: ${branch}）: ${createErr}"
            }
        } else {
            Write-Host "  [auto-pr] 既存 PR を更新しました: ${branch}"
        }
    } finally {
        Pop-Location
    }

    & git -C $Repo checkout $BaseBranch *> $null
}
