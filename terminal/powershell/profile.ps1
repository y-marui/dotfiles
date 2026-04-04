# PowerShell Profile
# zsh + Powerlevel10k lean スタイルに合わせた設定

# ─── Oh My Posh ──────────────────────────────────────────────────────────────
# インストール: brew install oh-my-posh (macOS) / winget install JanDeDobbeleer.OhMyPosh (Windows)
$_omp_config = "$HOME/.config/oh-my-posh/p10k-lean.json"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $_omp_config | Invoke-Expression
}

# ─── PSReadLine ───────────────────────────────────────────────────────────────
# zsh の Emacs キーバインド・履歴検索に合わせた設定
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord Ctrl+r  -Function ReverseSearchHistory
}
