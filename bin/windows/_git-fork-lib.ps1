# bin/windows/_git-fork-lib.ps1
# git-sweep.ps1・_ghq-lib.ps1（ghq-pull.ps1/ghq-update.ps1/ghq-sweep.ps1）から
# dot source される、GitHub 標準の fork 運用（`upstream` という名前の remote）に
# 関する共通関数。macOS/RPi の bin/unix/_git-fork-lib.sh に相当。
# ghq を前提としないため、ghq 系スクリプト専用の _ghq-lib.ps1 とは分離している。

Set-StrictMode -Version Latest

function Write-GitForkStderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

# Get-GitForkRemoteOwnerRepo <repo> <remote>
# <remote> の URL から owner/repo を切り出す。`gh repo view <url>` による解決は
# ~/.ssh/config の Host エイリアス（例: github-public:owner/repo.git）を解釈できない
# ため使わず、正規表現で抜き出す。
function Get-GitForkRemoteOwnerRepo([string]$Repo, [string]$Remote) {
    $url = (& git -C $Repo remote get-url $Remote 2>$null)
    if (-not $url) { return $null }
    $trimmed = $url -replace '\.git$', ''
    if ($trimmed -match '[:/]([^/]+/[^/]+)$') {
        return $Matches[1]
    }
    return $null
}

# Sync-GitForkUpstreamViaGit <repo>
# `gh` が使えない（未インストール・未認証）ときのフォールバック。upstream の
# デフォルトブランチを git だけで fetch し、origin の同名ブランチへ fast-forward で
# push する。認証は各 remote の URL（SSH 鍵等）にそのまま従う。
# 失敗（fetch/push 不可・diverge・origin にブランチ無し）は警告のみで例外は投げない。
function Sync-GitForkUpstreamViaGit([string]$Repo) {
    $branch = $null
    foreach ($line in @(& git -C $Repo ls-remote --symref upstream HEAD 2>$null)) {
        if ($line -match '^ref: refs/heads/(\S+)\s+HEAD$') { $branch = $Matches[1]; break }
    }
    if (-not $branch) {
        Write-GitForkStderr "  [skip upstream-sync] (${Repo}) upstream のデフォルトブランチを取得できませんでした"
        return
    }

    $global:LASTEXITCODE = $null
    $out = & git -C $Repo fetch --no-tags upstream "refs/heads/${branch}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $summary = (($out | Out-String) -replace "`r?`n", ' ').Trim()
        if ($summary.Length -gt 300) { $summary = $summary.Substring(0, 300) }
        Write-GitForkStderr "  [warn][upstream-sync] (${Repo}) upstream の fetch に失敗しました: ${summary}"
        return
    }
    $upSha = (& git -C $Repo rev-parse --verify -q FETCH_HEAD 2>$null)
    if (-not $upSha) {
        Write-GitForkStderr "  [warn][upstream-sync] (${Repo}) upstream/${branch} の取得結果を解決できませんでした"
        return
    }

    $global:LASTEXITCODE = $null
    & git -C $Repo fetch --no-tags origin "refs/heads/${branch}" *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-GitForkStderr "  [skip upstream-sync] (${Repo}) origin に ${branch} がありません、または fetch に失敗しました"
        return
    }
    $originSha = (& git -C $Repo rev-parse --verify -q FETCH_HEAD 2>$null)
    if ($originSha -eq $upSha) { return }

    $global:LASTEXITCODE = $null
    & git -C $Repo merge-base --is-ancestor $originSha $upSha *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-GitForkStderr "  [warn][upstream-sync] (${Repo}) origin/${branch} が upstream と分岐しているため同期しません（手動で確認してください）"
        return
    }

    $global:LASTEXITCODE = $null
    $pushOut = & git -C $Repo push origin "${upSha}:refs/heads/${branch}" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [upstream-sync] upstream と同期しました（git）: ${Repo}"
    } else {
        $summary = (($pushOut | Out-String) -replace "`r?`n", ' ').Trim()
        if ($summary.Length -gt 300) { $summary = $summary.Substring(0, 300) }
        Write-GitForkStderr "  [warn][upstream-sync] (${Repo}) push に失敗しました: ${summary}"
    }
}

# Sync-GitForkUpstream <repo>
# upstream という名前の remote があるリポジトリ（GitHub標準のfork運用）に限り、
# `gh repo sync` で upstream のデフォルトブランチを origin（自分のfork）へ
# fast-forward反映する（diverge していれば警告のみで自動マージはしない）。
# `gh` が使えない場合は Sync-GitForkUpstreamViaGit に切り替える。
# ローカルへの反映は、呼び出し元が続けて行う origin の fetch/pull に任せる。
# upstream remote が無いリポジトリには何もしない。失敗時も例外は投げない。
function Sync-GitForkUpstream([string]$Repo) {
    $upstreamRepo = Get-GitForkRemoteOwnerRepo $Repo 'upstream'
    if (-not $upstreamRepo) { return }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-GitForkStderr "  [upstream-sync] (${Repo}) 'gh' が見つからないため git で同期します"
        Sync-GitForkUpstreamViaGit $Repo
        return
    }

    Push-Location $Repo
    try {
        $global:LASTEXITCODE = $null
        & gh auth status *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-GitForkStderr "  [upstream-sync] (${Repo}) gh が未認証のため git で同期します"
            Sync-GitForkUpstreamViaGit $Repo
            return
        }

        $originRepo = Get-GitForkRemoteOwnerRepo $Repo 'origin'
        if (-not $originRepo) {
            Write-GitForkStderr "  [skip upstream-sync] (${Repo}) origin リポジトリを解決できませんでした"
            return
        }

        # 引数無しの gh repo sync はローカルの origin remote URL を gh 自身が解決する
        # ため、~/.ssh/config の Host エイリアス（例: github-public:owner/repo.git）を
        # 解釈できず失敗する。正規表現で抜き出し済みの owner/repo を明示的に渡す。
        $global:LASTEXITCODE = $null
        $syncOutput = & gh repo sync $originRepo --source $upstreamRepo 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [upstream-sync] upstream と同期しました: ${Repo}"
        } else {
            $syncSummary = (($syncOutput | Out-String) -replace "`r?`n", ' ').Trim()
            if ($syncSummary.Length -gt 500) { $syncSummary = $syncSummary.Substring(0, 500) }
            Write-GitForkStderr "  [warn][upstream-sync] (${Repo}) 同期に失敗しました（fast-forward不可の可能性があります。手動で確認してください）: ${syncSummary}"
        }
    } finally {
        Pop-Location
    }
}
