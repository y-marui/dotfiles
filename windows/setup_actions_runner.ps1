# private リポジトリ向けに、Windows のネイティブ GitHub Actions self-hosted runner を
# 専用ユーザー + Windows サービスで登録・解除する（ログオン不要で常駐する）。
# macos/setup_actions_runner.sh の Windows 版。方針・命名は macOS 版に揃える。
#
# 使い方（管理者の PowerShell で実行する。-DryRun と status は通常権限でもよい）:
#   pwsh windows/setup_actions_runner.ps1 install [-DryRun] OWNER/REPO...
#   pwsh windows/setup_actions_runner.ps1 status  OWNER/REPO...
#   pwsh windows/setup_actions_runner.ps1 uninstall [-DryRun] OWNER/REPO...
#
# 環境変数:
#   RUNNER_USER     専用ユーザー名（既定: ghrunner。管理者権限のない標準ユーザー）
#   RUNNER_LABEL    runner に付けるラベル（既定: windows-sh）
#   RUNNER_ROOT     runner の展開先（既定: C:\actions-runner。MAX_PATH を避けるため短い絶対パス）
#   RUNNER_VERSION  runner のバージョン（既定: 最新リリース）
#
# 方針と条件は dev-charter の topics/CI_POLICY-full.md「Runner Billing」を参照する。
# リポジトリ名はこのファイルに持たせない（引数で渡す）。登録トークンはファイルに残さない。
# runner 名は <ホスト名>-<repo>-win。同じホストの Linux runner（<ホスト名>-<repo>）と
# 同名にならないよう "win" を挟む（--replace で互いを置き換えないため）。

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = '',
    [switch]$DryRun,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Repos
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EnvOrDefault([string]$Name, [string]$Default) {
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($v)) { return $Default }
    return $v
}

$RunnerUser = Get-EnvOrDefault 'RUNNER_USER' 'ghrunner'
$RunnerLabel = Get-EnvOrDefault 'RUNNER_LABEL' 'windows-sh'
$RunnerRoot = Get-EnvOrDefault 'RUNNER_ROOT' 'C:\actions-runner'
$RunnerVersion = Get-EnvOrDefault 'RUNNER_VERSION' ''
$script:WorkTmp = $null
$script:Zip = $null

function Exit-Setup([string]$Message) {
    throw $Message
}

function Write-Step([string]$Message) {
    Write-Host "  $Message"
}

function Test-Administrator {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Gh {
    $out = & gh @args
    if ($LASTEXITCODE -ne 0) { Exit-Setup "gh $($args -join ' ') に失敗しました" }
    return ($out | Out-String).Trim()
}

function Get-RunnerName([string]$Repo) {
    return ('{0}-{1}-win' -f [Net.Dns]::GetHostName().ToLowerInvariant(), $Repo.Split('/')[1])
}

function Get-RunnerDir([string]$Repo) {
    return (Join-Path $RunnerRoot $Repo.Split('/')[1])
}

function Test-Preflight([string]$ActionName) {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') { Exit-Setup 'Windows 専用です' }
    if ($ActionName -ne 'status' -and -not $DryRun -and -not (Test-Administrator)) {
        Exit-Setup '管理者の PowerShell で実行してください（-DryRun と status は不要）'
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Exit-Setup 'gh がありません' }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { Exit-Setup 'gh が未認証です（gh auth login）' }
    if ($ActionName -eq 'install') {
        foreach ($tool in 'git', 'dotnet') {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                Exit-Setup "$tool がありません（CI が使う。システム全体の PATH に入れること）"
            }
        }
    }
    if ($ActionName -ne 'status') {
        $user = Get-LocalUser -Name $RunnerUser -ErrorAction SilentlyContinue
        if (-not $user) { Exit-Setup "ユーザー $RunnerUser がありません（docs/self-hosted-runner.md の Windows 手順 1）" }
        $admins = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*\$RunnerUser" }
        if ($admins) { Exit-Setup "$RunnerUser が管理者です。管理者権限のない標準ユーザーで実行してください" }
    }
}

# public リポジトリには登録しない（fork の PR が runner 上で任意のコードを実行できるため）
function Test-Repo([string]$Repo) {
    if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { Exit-Setup "OWNER/REPO の形式で指定してください: $Repo" }
    $private = Invoke-Gh api "repos/$Repo" --jq .private
    if ($private -ne 'true') { Exit-Setup "$Repo は public です。public には登録しません" }
}

function Get-Runner {
    if ($script:Zip) { return }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
    $endpoint = if ($RunnerVersion) { "repos/actions/runner/releases/tags/v$($RunnerVersion.TrimStart('v'))" } else { 'repos/actions/runner/releases/latest' }
    $jq = ".assets[] | select(.name | test(`"^actions-runner-$arch-[0-9.]+\\.zip`$`")) | [.name, (.digest // `"`"), .browser_download_url] | @tsv"
    $info = Invoke-Gh api $endpoint --jq $jq
    if (-not $info) { Exit-Setup "runner のアセットが見つかりません（$arch）" }
    $name, $digest, $url = $info -split "`t"
    if (-not $digest.StartsWith('sha256:')) { Exit-Setup '公式のチェックサム（digest）を取得できないため中止します' }
    $expected = $digest.Substring(7)

    $script:WorkTmp = Join-Path ([IO.Path]::GetTempPath()) ("runner-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkTmp | Out-Null
    $script:Zip = Join-Path $script:WorkTmp $name
    Write-Step "download $name"
    Invoke-WebRequest -Uri $url -OutFile $script:Zip -UseBasicParsing
    $actual = (Get-FileHash -Algorithm SHA256 -Path $script:Zip).Hash
    if ($actual -ne $expected.ToUpperInvariant()) { Exit-Setup "チェックサムが一致しません: $name" }
    Write-Step 'sha256 ok'
}

# runner の登録・削除用トークンを返す（1 時間で失効する。ファイルには残さない）
function Get-RunnerToken([string]$Repo, [string]$Kind) {
    return (Invoke-Gh api -X POST "repos/$Repo/actions/runners/$Kind-token" --jq .token)
}

function Wait-RunnerOnline([string]$Repo, [string]$RunnerName) {
    $status = ''
    for ($i = 0; $i -lt 30; $i++) {
        $status = & gh api "repos/$Repo/actions/runners" --jq ".runners[] | select(.name == `"$RunnerName`") | .status" 2>$null
        if ($status -eq 'online') { break }
        Start-Sleep -Seconds 2
    }
    if (-not $status) { $status = 'not-registered' }
    Write-Host ("  RUNNER  {0}: {1}" -f $RunnerName, $status)
    return ($status -eq 'online')
}

# サービス名は長いと切り詰められる（actions.runner.<scope>.<name の先頭>-<数字>）ため、
# 名前ではなく実行ファイルのパス（<runner のディレクトリ>\bin\RunnerService.exe）で特定する
function Get-RunnerService([string]$Dir) {
    $exe = Join-Path $Dir 'bin\RunnerService.exe'
    $wmi = Get-CimInstance Win32_Service -Filter "Name like 'actions.runner.%'" |
        Where-Object { $_.PathName -like "*$exe*" } | Select-Object -First 1
    if (-not $wmi) { return $null }
    return (Get-Service -Name $wmi.Name)
}

function Install-One([string]$Repo, [securestring]$Password) {
    $dir = Get-RunnerDir $Repo
    $runnerName = Get-RunnerName $Repo
    Write-Host "== $Repo"
    Test-Repo $Repo
    Get-Runner

    $account = ".\$RunnerUser"
    if ($DryRun) {
        Write-Step "+ mkdir $dir; icacls $dir /grant ${RunnerUser}:(OI)(CI)M"
        Write-Step "+ Expand-Archive <zip> -> $dir"
        Write-Step "+ gh api -X POST repos/$Repo/actions/runners/registration-token"
        Write-Step "+ $dir\config.cmd --unattended --url https://github.com/$Repo --token <token> --name $runnerName --labels $RunnerLabel --work _work --replace --runasservice --windowslogonaccount $account --windowslogonpassword <password>"
        return
    }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # 専用ユーザーだけが書き込める（継承を切り、Administrators / SYSTEM / runner ユーザーのみ）
    & icacls $dir /inheritance:r /grant:r 'Administrators:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' "${RunnerUser}:(OI)(CI)M" | Out-Null
    if (-not (Test-Path (Join-Path $dir 'config.cmd'))) {
        Write-Step "extract runner -> $dir"
        Expand-Archive -Path $script:Zip -DestinationPath $dir -Force
    }

    if (-not (Test-Path (Join-Path $dir '.runner'))) {
        Write-Step "register runner ($runnerName, label $RunnerLabel)"
        $Password = Read-Host "$RunnerUser のパスワード（サービスのログオンに使う。保存しない）" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
        Push-Location $dir
        try {
            # トークンは 1 時間で失効する登録専用の値。パスワードはサービスの logon 設定にだけ使い、保存しない
            & .\config.cmd --unattended --url "https://github.com/$Repo" --token (Get-RunnerToken $Repo 'registration') `
                --name $runnerName --labels $RunnerLabel --work _work --replace `
                --runasservice --windowslogonaccount $account --windowslogonpassword $plain
            if ($LASTEXITCODE -ne 0) { Exit-Setup 'config.cmd に失敗しました' }
        } finally {
            Pop-Location
            $plain = $null
        }
    } else {
        Write-Step 'already registered (skip config)'
    }

    # actions/setup-dotnet は既定で共有の C:\Program Files\dotnet に書こうとして、標準ユーザーでは失敗する。
    # runner 専用のディレクトリに向ける（hosted runner と同じく、ジョブごとに必要な SDK を入れられる）
    $envFile = Join-Path $dir '.env'
    $envText = "DOTNET_INSTALL_DIR=$dir\_dotnet`r`nDOTNET_CLI_TELEMETRY_OPTOUT=1`r`n"
    $changed = (-not (Test-Path $envFile)) -or ((Get-Content $envFile -Raw) -ne $envText)
    if ($changed) {
        [IO.File]::WriteAllText($envFile, $envText, (New-Object Text.UTF8Encoding $false))
        Write-Step "write $envFile"
        $svc = Get-RunnerService $dir
        if ($svc) {
            Restart-Service -InputObject $svc
            Write-Step "restart $($svc.Name)"
        }
    }
    if (-not (Wait-RunnerOnline $Repo $runnerName)) {
        Write-Step "オンラインを確認できません。サービス: Get-Service 'actions.runner.*'、ログ: $dir\_diag\"
    }
}

function Uninstall-One([string]$Repo) {
    $dir = Get-RunnerDir $Repo
    Write-Host "== $Repo"
    if ($DryRun) {
        Write-Step "+ gh api -X POST repos/$Repo/actions/runners/remove-token"
        Write-Step "+ $dir\config.cmd remove --token <token>"
        Write-Step "+ Remove-Item -Recurse -Force $dir"
        return
    }
    if (Test-Path (Join-Path $dir '.runner')) {
        Push-Location $dir
        try {
            & .\config.cmd remove --token (Get-RunnerToken $Repo 'remove')
        } finally {
            Pop-Location
        }
    }
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    Write-Step "removed $dir"
}

function Show-Status([string]$Repo) {
    $runnerName = Get-RunnerName $Repo
    $svc = Get-RunnerService (Get-RunnerDir $Repo)
    if ($svc) { Write-Host ("  SERVICE {0}: {1}" -f $svc.Name, $svc.Status) } else { Write-Host '  SERVICE absent' }
    $remote = & gh api "repos/$Repo/actions/runners" --jq ".runners[] | select(.name == `"$runnerName`") | .status" 2>$null
    if (-not $remote) { $remote = 'unknown' }
    Write-Host ("  GITHUB  {0}: {1}" -f $runnerName, $remote)
}

try {
    if (-not $Action) { Exit-Setup '使い方: setup_actions_runner.ps1 {install|status|uninstall} [-DryRun] OWNER/REPO...' }
    if (-not $Repos -or $Repos.Count -eq 0) { Exit-Setup 'OWNER/REPO を 1 つ以上指定してください' }
    Test-Preflight $Action

    switch ($Action) {
        'install' {
            foreach ($repo in $Repos) { Install-One $repo $null }
        }
        'uninstall' { foreach ($repo in $Repos) { Uninstall-One $repo } }
        'status' { foreach ($repo in $Repos) { Write-Host "== $repo"; Show-Status $repo } }
        default { Exit-Setup "不明なアクション: $Action" }
    }
} finally {
    if ($script:WorkTmp -and (Test-Path $script:WorkTmp)) { Remove-Item -Recurse -Force $script:WorkTmp }
}
