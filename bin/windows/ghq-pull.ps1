#!/usr/bin/env pwsh
# ghq-pull: ghq 管理リポジトリの全リポジトリを fetch + pull する
#
# 使い方:
#   ghq-pull [options]
#
# オプション:
#   --fetch-only        fetch のみ実行（ローカルブランチは更新しない）
#   -f, --filter PATTERN  リポジトリパスが正規表現 PATTERN にマッチするものだけを対象にする
#   -h, --help          ヘルプを表示
#
# 動作:
#   各リポジトリで git-pull-all を実行する（詳細は git-pull-all を参照）。
#   - upstream という名前の remote があれば、先に `gh repo sync` で upstream の
#     デフォルトブランチを origin へ fast-forward 反映する
#     （diverge していれば警告のみ。gh 未インストール・未認証ならスキップ）
#   - git fetch --all --prune を実行する（dirty・detached HEAD でも実行）
#   - 現在のブランチを pull --ff-only で更新する。dirty・detached HEAD・upstream 未設定の
#     場合は更新せず warning を出す。現在のブランチ以外（保護ブランチを含む）の
#     ローカルブランチも、upstream へ fast-forward で同期する
#   - uv.lock/package-lock.json のみ dirty な場合は一時的に stash して pull し、
#     pull 後に復元する（復元時にコンフリクトした場合は stash を残したまま失敗として扱う）
#   - 失敗（fetch 失敗・pull 失敗・stash 復元失敗）したリポジトリは [failed] を表示し、
#     処理は続行して、最後に終了コード1で終了する（スキップ・警告は終了コード0）

Set-StrictMode -Version Latest

. "$PSScriptRoot\_ghq-lib.ps1"

function Show-Help {
    $lines = @(Get-Content -LiteralPath $PSCommandPath)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -eq '') { break }
        Write-Host ($line -replace '^#\s?', '')
    }
}

$FETCH_ONLY = $false
$FILTER = ''

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -eq '--fetch-only') {
        $FETCH_ONLY = $true
        $i++
    } elseif ($arg -eq '-f' -or $arg -eq '--filter') {
        if ($i + 1 -ge $args.Count) {
            Write-GhqStderr "error: --filter requires an argument"
            exit 1
        }
        $FILTER = $args[$i + 1]
        $i += 2
    } elseif ($arg -eq '-h' -or $arg -eq '--help') {
        Show-Help
        exit 0
    } else {
        Write-GhqStderr "error: unknown option: $arg"
        exit 1
    }
}

if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
    Write-GhqStderr "error: 'ghq' が見つかりません。"
    exit 1
}

$repos = Get-GhqOrderedList $FILTER

$failed = 0
$pullArgs = @()
if ($FETCH_ONLY) { $pullArgs += '--fetch-only' }

foreach ($f in $repos) {
    Write-Host ""
    Write-Host "==> $f"
    if (-not (Invoke-GhqPullRepo $f $pullArgs)) { $failed++ }
}

if ($failed -gt 0) { exit 1 }
