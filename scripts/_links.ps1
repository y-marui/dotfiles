# scripts/_links.ps1
# install.ps1 / check.ps1 / uninstall.ps1 から dot source される。
# macOS/Raspberry Pi の scripts/_links.sh に相当する Windows 版のリンク定義。
#
# 使い方: . "$PSScriptRoot\_links.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DOTFILES_DIR = Split-Path -Parent $PSScriptRoot
$PRIVATE_DIR = "$DOTFILES_DIR-private"

$Links = @(
    [pscustomobject]@{
        # dots・git-sweep・git-survey・ghq-pull・ghq-update・ghq-sweep・ghq-check・
        # ghq-status・run-quiet 等（*.ps1 でネイティブ移植し、bareコマンド名で呼べる
        # よう *.cmd を同梱）をまとめてリンクする（macOS/RPiの bin/unix ->
        # ~/.local/bin/dotfiles 相当）。bin/unix と bin/windows のコマンド対応は
        # scripts/check-bin-parity.sh が pre-commit で検証する。
        Src  = "bin\windows"
        Dest = Join-Path $HOME ".local\bin\dotfiles"
    }
    [pscustomobject]@{
        Src  = "terminal\powershell\profile.ps1"
        # OneDrive の「ドキュメント」リダイレクトを含む、pwsh が実際に読むパス。
        Dest = $PROFILE.CurrentUserCurrentHost
    }
    [pscustomobject]@{
        Src  = "terminal\windows-terminal\dotfiles.json"
        # 自動attachを迂回できる「PowerShell (No Zellij)」プロファイル。
        Dest = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\dotfiles\profiles.json"
    }
    [pscustomobject]@{
        Src  = "terminal\ohmyposh\p10k-lean.json"
        Dest = Join-Path $HOME ".config\oh-my-posh\p10k-lean.json"
    }
    [pscustomobject]@{
        Src  = "terminal\zellij\windows\config.kdl"
        Dest = Join-Path $HOME ".config\zellij\config.kdl"
    }
    [pscustomobject]@{
        Src  = "git\gitconfig"
        Dest = Join-Path $HOME ".gitconfig"
    }
    [pscustomobject]@{
        Src  = "git\gitignore_global"
        Dest = Join-Path $HOME ".gitignore_global"
    }
    [pscustomobject]@{
        Src  = "git\hooks"
        Dest = Join-Path $HOME ".config\git\hooks"
    }
    [pscustomobject]@{
        Src  = "git\gitconfig.d\aliases.gitconfig"
        Dest = Join-Path $HOME ".gitconfig.d\aliases.gitconfig"
    }
    [pscustomobject]@{
        # Windows 純正 OpenSSH に core.sshCommand を向け、ssh-agent サービス経由の
        # 認証にする（Git バンドルの usr/bin/ssh.exe は毎回パスフレーズを要求する）。
        Src  = "git\gitconfig.d\windows.gitconfig"
        Dest = Join-Path $HOME ".gitconfig.d\os"
    }
    [pscustomobject]@{
        Src  = "ai\AI_CONTEXT.md"
        Dest = Join-Path $HOME ".ai\AI_CONTEXT.md"
    }
    [pscustomobject]@{
        Src  = "ai\AI_CONTEXT_CLI.md"
        Dest = Join-Path $HOME ".ai\AI_CONTEXT_CLI.md"
    }
    [pscustomobject]@{
        Src  = "ai\AI_CONTEXT.md"
        Dest = Join-Path $HOME ".codex\AGENTS.md"
    }
    [pscustomobject]@{
        Src  = "ai\claude\settings.json"
        Dest = Join-Path $HOME ".claude\settings.json"
    }
    [pscustomobject]@{
        Src  = "ai\claude\CLAUDE.md"
        Dest = Join-Path $HOME ".claude\CLAUDE.md"
    }
    [pscustomobject]@{
        Src  = "ai\claude\hooks\status.sh"
        Dest = Join-Path $HOME ".claude\hooks\status.sh"
    }
    [pscustomobject]@{
        Src  = "ai\copilot\instructions.md"
        Dest = Join-Path $HOME ".copilot\copilot-instructions.md"
    }
    [pscustomobject]@{
        Src  = "ai\gemini\GEMINI.md"
        Dest = Join-Path $HOME ".gemini\GEMINI.md"
    }
)

# 共通 skill と agent 専用 skill はディレクトリ全体ではなく、SKILL.md を持つものだけを
# 個別リンクする。scripts/_links.sh の同名ロジックと揃える。
foreach ($agent in @("codex", "claude")) {
    $skillHome = if ($agent -eq "codex") { Join-Path $HOME ".agents\skills" } else { Join-Path $HOME ".claude\skills" }

    $seenSkillNames = @{}
    foreach ($sourceHome in @((Join-Path $DOTFILES_DIR "ai\skills"), (Join-Path $DOTFILES_DIR "ai\$agent\skills"))) {
        if (-not (Test-Path $sourceHome)) { continue }

        Get-ChildItem -LiteralPath $sourceHome -Directory | ForEach-Object {
            $skillFile = Join-Path $_.FullName "SKILL.md"
            if (-not (Test-Path $skillFile)) { return }

            $skillName = $_.Name
            if ($seenSkillNames.ContainsKey($skillName)) {
                throw "共通 skill と ${agent} 専用 skill で名前が重複しています: ${skillName}"
            }
            $seenSkillNames[$skillName] = $true

            $skillSource = $_.FullName.Substring($DOTFILES_DIR.Length + 1)
            $Links += [pscustomobject]@{
                Src  = $skillSource
                Dest = Join-Path $skillHome $skillName
            }
        }
    }
}

# dotfiles-private は設定データとリンク対応表だけを保持する。
# links.conf は実行せず、platform|source|destination の3列として厳格に読む。
$PrivateLinks = @()
$InactivePrivateLinks = @()
$PrivateLinksFile = Join-Path $PRIVATE_DIR 'links.conf'

function Test-PrivateRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^[\\/~]') { return $false }
    if ($Path -match '(^|/)\.\.?(/|$)') { return $false }
    if ($Path -match '[\\:]') { return $false }
    return $true
}

if (Test-Path -LiteralPath $PRIVATE_DIR -PathType Container) {
    if (-not (Test-Path -LiteralPath $PrivateLinksFile -PathType Leaf)) {
        throw "$PrivateLinksFile が見つかりません。dotfiles-private を更新してください。"
    }

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $PrivateLinksFile) {
        $lineNumber++
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }

        $parts = $line.Split('|')
        if ($parts.Count -ne 3) {
            throw "${PrivateLinksFile}:${lineNumber}: platform|source|destination の3列ではありません。"
        }

        $platform = $parts[0].Trim()
        $sourceRelative = $parts[1].Trim()
        $destinationRelative = $parts[2].Trim()
        if ($platform -notin @('all', 'unix', 'darwin', 'windows')) {
            throw "${PrivateLinksFile}:${lineNumber}: 未対応platform: $platform"
        }
        if (-not (Test-PrivateRelativePath $sourceRelative) -or
            -not (Test-PrivateRelativePath $destinationRelative)) {
            throw "${PrivateLinksFile}:${lineNumber}: 相対パスが不正です。"
        }

        $source = Join-Path $PRIVATE_DIR ($sourceRelative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $source)) {
            throw "${PrivateLinksFile}:${lineNumber}: sourceが存在しません: $sourceRelative"
        }
        $destination = Join-Path $HOME ($destinationRelative.Replace('/', '\'))
        $knownDestinations = @($Links | ForEach-Object { $_.Dest }) +
            @($PrivateLinks | ForEach-Object { $_.Dest }) +
            @($InactivePrivateLinks | ForEach-Object { $_.Dest })
        if ($knownDestinations | Where-Object { $_ -ieq $destination }) {
            throw "${PrivateLinksFile}:${lineNumber}: destinationが重複しています: $destinationRelative"
        }

        $link = [pscustomobject]@{
            Src  = $sourceRelative.Replace('/', '\')
            Dest = $destination
        }
        if ($platform -in @('all', 'windows')) {
            $PrivateLinks += $link
        } else {
            $InactivePrivateLinks += $link
        }
    }
}
