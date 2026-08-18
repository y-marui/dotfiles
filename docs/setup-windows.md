# Windows セットアップ

Windows Terminal / PowerShell 7を利用するWindows環境向けの手順。

## 前提ツール

- PowerShell 7 (`pwsh`)
- Git
- GNU Make (`mingw32-make`でも可)
- gsudo

gsudoが未導入の場合は、PowerShellで以下を実行してからコンソールを開き直す。

```powershell
winget install gerardog.gsudo
```

## 初回セットアップ

初回はUACダイアログを操作できるMRDなどの対話デスクトップセッションで実行する。

```powershell
cd path\to\dotfiles
mingw32-make install
```

`scripts/setup-gsudo.ps1`は次の設定を行う。最初の`gsudo`実行でUACを承認すると、
呼び出し元プロセスとその子プロセスに限定した30分の認証キャッシュが開始される。

```powershell
gsudo config CacheMode Auto
gsudo config CacheDuration 00:30:00
```

全プロセスを対象にする`gsudo cache on -p 0`は使用しない。管理者権限が必要な
作業はMRDから開始し、キャッシュの対象を呼び出し元のプロセスツリーに限定する。
作業後や端末を離れる前にキャッシュを明示的に終了できる。

```powershell
gsudo cache off
```

## Zellijの継続起動

Windowsではネイティブ対応とWindows固有の修正を含むZellij `0.44.3`を使用する。
macOS/Raspberry Piで固定している`0.43.1`とは別に管理する。

`make install`と`dots update`は`scripts/setup-zellij.ps1`を実行し、公式ZIPと
展開後の`zellij.exe`のSHA-256を検証して`~\.local\bin`へインストールする。
インストールせず配布物だけを検証する場合は`-VerifyOnly`を指定できる。

```powershell
pwsh -NoProfile -File scripts/setup-zellij.ps1 -VerifyOnly
```

PowerShellプロファイルはWindows TerminalまたはSSHからホスト名セッションへ
自動アタッチする。最初の対話的な接続がセッションを作成し、切断後はZellijサーバーが
バックグラウンドで動き続ける。`SHELL`にはPowerShell 7の実行パスを設定するため、
Zellijで追加するペインも`cmd.exe`ではなく`pwsh.exe`になる。Windows専用の
`terminal/zellij/windows/config.kdl`でも`default_shell "pwsh.exe"`を明示する。

Windows版`0.44.3`では`attach --create-background`で事前作成したセッションの入力が
PowerShellとcmd.exeの両方で処理されないことを確認している。そのためScheduled Taskで
セッションを事前作成せず、必ず実際のTerminalまたはSSH接続から作成する。

Windows Terminalを閉じても、独立したZellijサーバーとその中のプロセスは終了しない。
次回のTerminalまたはSSH接続時には同じホスト名セッションへ戻る。

Zellijを使わないPowerShellが必要な場合は、Windows Terminalの新しいタブメニューから
`PowerShell (No Zellij)`を選ぶ。このプロファイルだけ`NO_ZELLIJ=1`を設定するため、
通常のPowerShell設定は読み込みつつZellijへの自動アタッチをスキップする。

確認コマンド:

```powershell
zellij list-sessions
Get-Process -Name zellij -ErrorAction SilentlyContinue
```

想定されるセッション名は次のコマンドで確認できる。

```powershell
($env:COMPUTERNAME -split '\.')[0].ToLower()
```

## 更新

```powershell
dots update
```

`dots` は `make install` により `~\.local\bin` へリンクされるため、dotfilesの
リポジトリ外からも実行できる。`dots status` ではdotfilesとdotfiles-privateの
未コミット・未push・未pullをまとめて確認できる。

Windows版の更新は次の順に実行する。

1. ローカル変更がなければdotfilesを`git pull --ff-only`で更新
2. シンボリックリンクを再適用
3. Zellijを更新
4. WinGetパッケージとWindows Updateを適用
5. 利用可能な場合はnpm、pipx、ghq管理下のリポジトリを更新

旧`make update`が作成したWinLibsのpinが残っている場合は自動的に解除し、WinLibsも
WinGetの一括更新に含める。
