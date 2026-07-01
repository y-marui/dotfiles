# PowerShell Profile
# zsh + Powerlevel10k lean スタイルに合わせた設定
# 対象環境: Windows（Windows Terminal）、macOS/Linux（pwsh）

# ─── Zellij 自動アタッチ ─────────────────────────────────────────────────────
# Windows Terminal または SSH 接続時のみ起動。NO_ZELLIJ=1 でスキップ。
if ((Get-Command zellij -ErrorAction SilentlyContinue) -and
    -not $env:ZELLIJ -and
    -not $env:NO_ZELLIJ -and
    ($env:WT_SESSION -or $env:SSH_CONNECTION)) {
    $sessionName = ($env:COMPUTERNAME -split '\.')[0].ToLower()
    zellij attach -c $sessionName
    exit
}

# ─── Oh My Posh ──────────────────────────────────────────────────────────────
# インストール: winget install JanDeDobbeleer.OhMyPosh (Windows)
#              brew install oh-my-posh (macOS)
$_omp_config = "$HOME/.config/oh-my-posh/p10k-lean.json"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $_omp_config | Invoke-Expression
}

# ─── Terminal-Icons ───────────────────────────────────────────────────────────
# ls の出力にファイルタイプアイコンを追加（zsh の ls -G + Nerd Font 相当）
# インストール: Install-Module -Name Terminal-Icons -Repository PSGallery
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# ─── PSReadLine ───────────────────────────────────────────────────────────────
# zsh の Emacs キーバインド・履歴検索・構文ハイライトに合わせた設定
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord Ctrl+r  -Function ReverseSearchHistory
    # p10k lean カラーパレットに合わせた構文ハイライト
    Set-PSReadLineOption -Colors @{
        Command          = '#5fd700'  # green (prompt char と同色)
        Parameter        = '#0087af'  # blue (dir segment と同色)
        String           = '#d7af00'  # yellow (git dirty と同色)
        Variable         = '#5fd700'
        Comment          = '#808080'  # grey (time segment と同色)
        Keyword          = 'White'
        Error            = '#ff0000'  # red (error prompt char と同色)
        InlinePrediction = '#585858'  # dark grey
    }
}

# ─── PSFzf ────────────────────────────────────────────────────────────────────
# fzf によるファイル・履歴・補完の強化（zsh の fzf integration 相当）
# Ctrl+T: ファイル検索、Ctrl+R: 履歴検索（fzf版）、Tab: fzf補完
# インストール: Install-Module -Name PSFzf -Repository PSGallery
#              winget install junegunn.fzf
if ((Get-Module -ListAvailable -Name PSFzf) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadLineChordProvider       'Ctrl+t'
    Set-PsFzfOption -PSReadLineChordReverseHistory  'Ctrl+r'
    Set-PsFzfOption -TabExpansion
}

# ─── ZLocation (z) ────────────────────────────────────────────────────────────
# cd 履歴を学習してスマートジャンプ（zprezto directory モジュール / zsh-z 相当）
# インストール: Install-Module -Name z -Repository PSGallery
if (Get-Module -ListAvailable -Name z) {
    Import-Module z
}

# ─── SSH ラッパー（Zellij 内のみ有効）────────────────────────────────────────
# Zellij 内で ssh を実行すると新しいペイン/タブを作成して SSH を起動する。
# 接続先ではデフォルトで zellij auto-attach（NO_ZELLIJ='' を渡す）。
# 使い方: ssh [--new] [--no-zellij] <ssh args...>
#   --new       : 新規タブで開く（デフォルトは縦分割ペイン）
#   --no-zellij : 接続先の zellij auto-attach を無効化
if ($env:ZELLIJ) {
    function Invoke-Ssh {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

        $newTab   = $false
        $noZellij = $false
        $sshArgs  = @()

        foreach ($arg in $Arguments) {
            switch ($arg) {
                '--new'       { $newTab   = $true }
                '--no-zellij' { $noZellij = $true }
                default       { $sshArgs += $arg }
            }
        }

        $noZellijEnv = "NO_ZELLIJ=''"
        if ($noZellij) { $noZellijEnv = 'NO_ZELLIJ=1' }

        $remoteHost = $sshArgs[-1]
        $sshCmd     = "env $noZellijEnv ssh $($sshArgs -join ' ')"

        if ($newTab) {
            zellij action new-pane --new-tab --name "ssh:$remoteHost" --close-on-exit -- sh -c $sshCmd
        } else {
            zellij run --name "ssh:$remoteHost" --close-on-exit -- sh -c $sshCmd
        }
    }
    Set-Alias -Name ssh -Value Invoke-Ssh -Force
}

# ─── カスタム関数 ──────────────────────────────────────────────────────────────

# cd 後に自動で ls（zsh の `function cd() { builtin cd "$@" && ls }` 相当）
function Set-LocationWithList {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Path
    )
    if ($Path) { Set-Location @Path } else { Set-Location }
    Get-ChildItem
}
Set-Alias -Name cd -Value Set-LocationWithList -Option AllScope -Force

# ghq + fzf でリポジトリ移動（zsh の g() 関数相当）
# 使い方: g [root]
function g {
    param([string]$Command)
    switch ($Command) {
        'root' { ghq root }
        default {
            $target = ghq list -p | Sort-Object | fzf
            if ($target) {
                Write-Host $target
                Set-Location $target
            }
        }
    }
}

# ghq リポジトリの local.keep-up-to-date 状態を一覧表示
function ghq-status {
    $root = ghq root
    ghq list -p | Sort-Object | ForEach-Object {
        $repo = $_
        $val  = git -C $repo config local.keep-up-to-date 2>$null
        $rel  = $repo.Replace("$root\", '').Replace("$root/", '')
        if ($val -eq 'true')       { Write-Host "[keep]  $rel" -ForegroundColor Green }
        elseif ($val -eq 'false')  { Write-Host "[skip]  $rel" -ForegroundColor Red   }
        else                       { Write-Host "[----]  $rel" }
    }
}

Set-Alias make mingw32-make

# ─── dotfiles 未コミット・未プッシュ確認 ───────────────────────────────────────
# $env:DOTFILES_DIR は環境変数または ~\.profile.ps1 で設定しておく
if ($env:DOTFILES_DIR -and (Test-Path "$env:DOTFILES_DIR/.git")) {
    $dfMsgs = @()
    if (git -C $env:DOTFILES_DIR status --porcelain 2>$null) {
        $dfMsgs += '未コミットの変更あり'
    }
    $dfUnpushed = (git -C $env:DOTFILES_DIR log '@{u}..' --oneline 2>$null | Measure-Object -Line).Lines
    if ($dfUnpushed -gt 0) { $dfMsgs += "$dfUnpushed commits unpushed" }
    if ($dfMsgs) { Write-Host "⚠ dotfiles: $($dfMsgs -join ' / ')" -ForegroundColor Yellow }
}
