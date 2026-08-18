# bin/_ghq-lib.ps1
# ghq-pull.ps1 / ghq-update.ps1 から dot source される共通関数。
# macOS/RPi の bin/_ghq-lib.sh に相当。
#
# uv.lock はローカルの `uv sync` 等で頻繁に更新され、コミットされていない
# 差分を抱えやすい。これだけを理由に dirty working tree として処理全体を
# スキップしてしまうと ghq-pull / ghq-update が実質的に動かなくなるため、
# uv.lock のみが dirty な場合は一時的に stash して処理を継続し、処理後に
# 復元する。uv.lock 以外にも dirty な変更がある場合は従来通りスキップする。

Set-StrictMode -Version Latest

function Write-GhqStderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

$Script:GhqStashed = $false

# Push-GhqUvLockStash <repo>
# 戻り値 $true : 処理続行可（clean、または uv.lock のみ dirty で stash 済み）
# 戻り値 $false: uv.lock 以外にも dirty な変更があるためスキップすべき
function Push-GhqUvLockStash([string]$Repo) {
    $Script:GhqStashed = $false
    $porcelain = @(& git -C $Repo status --porcelain 2>$null)
    if (-not $porcelain) { return $true }

    $other = @($porcelain | Where-Object { $_ -notmatch ' uv\.lock$' })
    if ($other.Count -gt 0) { return $false }

    $global:LASTEXITCODE = $null
    & git -C $Repo stash push --include-untracked --quiet --message 'ghq-lib: uv.lock' -- uv.lock
    if ($LASTEXITCODE -ne 0) { return $false }
    $Script:GhqStashed = $true
    return $true
}

# Pop-GhqUvLockStash <repo>
# Push-GhqUvLockStash で stash した uv.lock を復元する。
# pull 等でリモート側も uv.lock を更新していた場合はコンフリクトしうるため、
# その場合は stash を残したまま失敗を報告する（自動では解決しない）。
function Pop-GhqUvLockStash([string]$Repo) {
    if (-not $Script:GhqStashed) { return $true }

    $global:LASTEXITCODE = $null
    & git -C $Repo stash pop --quiet
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-GhqStderr "  [conflict] uv.lock の復元に失敗（手動で解決してください: cd ${Repo} && git stash list）"
    return $false
}

$Script:GhqAutoPrBranch = 'chore/uv-lock-update'

# Invoke-GhqAutoPrUvLock <repo> <base_branch>
# uv sync --upgrade により uv.lock のみが dirty な場合、専用ブランチに
# コミットして force push し、gh で PR を作成する（既に open な PR が
# あれば push だけでその PR に反映される）。作業ツリーは base_branch に
# 戻した状態で返す。失敗時も呼び出し元の処理は継続できるよう例外は投げない。
function Invoke-GhqAutoPrUvLock([string]$Repo, [string]$BaseBranch) {
    $branch = $Script:GhqAutoPrBranch

    $uvStatus = @(& git -C $Repo status --porcelain -- uv.lock 2>$null)
    if (-not $uvStatus) { return }

    $allStatus = @(& git -C $Repo status --porcelain 2>$null)
    $other = @($allStatus | Where-Object { $_ -notmatch ' uv\.lock$' })
    if ($other.Count -gt 0) {
        Write-GhqStderr "  [skip auto-pr] uv.lock 以外にも dirty な変更があります"
        return
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-GhqStderr "  [skip auto-pr] 'gh' が見つかりません（uv.lock の変更はローカルに残しています）"
        return
    }

    Push-Location $Repo
    try {
        $global:LASTEXITCODE = $null
        & gh auth status *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-GhqStderr "  [skip auto-pr] gh が未認証です（uv.lock の変更はローカルに残しています）"
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
        Write-GhqStderr "  [skip auto-pr] origin リポジトリを解決できませんでした"
        return
    }

    $global:LASTEXITCODE = $null
    & git -C $Repo checkout -B $branch *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-GhqStderr "  [skip auto-pr] ブランチ作成に失敗しました"
        return
    }
    $global:LASTEXITCODE = $null
    & git -C $Repo commit -m 'chore: update uv.lock' -- uv.lock *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-GhqStderr "  [skip auto-pr] commit に失敗しました"
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
            $global:LASTEXITCODE = $null
            $createErr = & gh pr create --repo $ghRepo --title 'chore: update uv.lock' `
                --body 'uv sync --upgrade により生成された uv.lock の更新です（ghq-update の自動 PR 機能）。' `
                --base $BaseBranch --head $branch 2>&1
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
