# macOS セットアップ手順

新規 Mac に開発環境を構築するための手順。

## 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Xcode Command Line Tools も同時にインストールされる。

**Apple Silicon (M1/M2/M3) の場合:** インストール後、新しいターミナルを開くか以下を実行して PATH を有効にする。

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## 2. Generate and Register an SSH Key

GitHub およびその他サービスへの SSH キーを設定する。

```bash
# GitHub 用（Ed25519 推奨）
ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519_github

# ssh-agent に登録（Keychain に保存）
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_github
```

再起動後も Keychain から自動読み込みされるよう `~/.ssh/config` に追記する:

```
Host github.com
  UseKeychain yes
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519_github
```

公開鍵を GitHub に登録する（[github.com/settings/keys](https://github.com/settings/keys)）:

```bash
pbcopy < ~/.ssh/id_ed25519_github.pub
# クリップボードにコピーされるので GitHub の設定画面に貼り付ける
```

接続確認:

```bash
ssh -T git@github.com
```

## 3. Fetch dotfiles with ghq

```bash
brew install ghq
git config --global ghq.root ~/src

ghq get https://github.com/y-marui/dotfiles.git
# → ~/src/github.com/y-marui/dotfiles/ に配置される
cd ~/src/github.com/y-marui/dotfiles
```

> SSH キーが未設定の場合は、GitHub から ZIP でダウンロードして展開しても構わない。

## 4. Install zprezto

zsh テーマ・補完等は zprezto に依存している。共通セットアップスクリプトで
Prezto 本体とサブモジュールの Powerlevel10k を導入する。

```bash
bash scripts/setup-prezto.sh
```

`make install-macos` でも同じスクリプトを実行するため、この手順は再実行しても安全。
ZDOTDIR を設定していない標準環境では `~/.zprezto` にクローンされる。

## 5. Generate and Edit Host-Specific Settings

```bash
make init
```

以下の5ファイルが生成される:

- `host/<hostname>.zsh` — zsh のマシン固有設定
- `host/<hostname>.gitconfig` — gitconfig のマシン固有設定
- `~/.zshrc.local` — zsh 追加設定（自動読み込み）
- `~/.bashrc.local` — bash 追加設定（自動読み込み）
- `macos/Brewfile.local` — このマシン固有の Homebrew パッケージ

必要に応じて編集する:

```bash
# ghq でクローンした場合、配置先は ~/dotfiles ではなく
# ~/src/github.com/y-marui/dotfiles になるため DOTFILES_DIR の設定が必要
vi ~/.zshrc.local   # DOTFILES_DIR=~/src/github.com/y-marui/dotfiles を設定

vi ./host/$(hostname -s).zsh
```

## 6. Fetch Private Settings

gitconfig（user.name / user.email / signingkey 等）は `dotfiles-private` で管理している。
`make private` は `gh` CLI を使用するため、事前にインストールと認証が必要:

```bash
brew install gh
gh auth login
```

`scripts/.env` に取得先リポジトリを設定して実行:

```bash
vi scripts/.env     # PRIVATE_REPO を記入（例: y-marui/dotfiles-private）
make private
# .env が存在しない場合はスクリプトが .env.example からコピーして終了するので、
# 記入後に再度 make private を実行する
```

## 7. Install dotfiles

`make install-macos` は `make private` 済みであれば `dotfiles-private/setup.sh` も自動適用する。

```bash
make install-macos
# install（シンボリックリンク）+ dots check監視 + macos（defaults）+ brew（Brewfile）+ dock を一括適用
```

整合性を確認:

```bash
make check
```

## 8. Install iTerm2 Shell Integration

iTerm2 メニュー → **iTerm2 > Install Shell Integration** を実行する。

## 9. Save and Load iTerm2 Settings in dotfiles

iTerm2 の設定ファイル（plist）を dotfiles 内で管理し、複数 Mac 間で共有する。

**初回（設定を保存する側）:**

1. iTerm2 の設定を希望の状態にする
2. **iTerm2 > Settings > General > Preferences** を開く
3. "Load preferences from a custom folder or URL" を有効にする
4. フォルダを dotfiles 内のパスに設定する:

```
~/src/github.com/y-marui/dotfiles/terminal/iterm2
```

5. "Save changes to folder when iTerm2 quits" を有効にする

**他の Mac で読み込む場合:**

同様に "Load preferences from a custom folder or URL" を有効にして、上記のパスを指定するだけでよい（dotfiles 取得後に実施）。

## 10. Set Up Cloud Storage

Brewfile でインストール済みの場合はサインインのみ行う。手動でインストールする場合は以下:

```bash
brew install --cask dropbox
brew install --cask onedrive
brew install --cask google-drive
```

各アプリを起動してアカウント認証・同期設定を行う。

> Dropbox は Alfred の設定同期に使用するため、他のサービスより先にセットアップしておく。

## 11. Sync Alfred Settings to Dropbox

Alfred の設定を Dropbox 経由で複数 Mac に同期する。

1. Dropbox の同期が完了していることを確認する
2. **Alfred Preferences > Advanced > Syncing** を開く
3. "Set preferences folder..." をクリックし、Dropbox 内のフォルダを指定する:

```
~/Dropbox/Alfred
```

別の Mac で同じ Dropbox フォルダを指定すると設定が共有される。

## 12. Set Up Tailscale

VPN メッシュネットワークで複数デバイスを接続する。

```bash
brew install --cask tailscale
```

または Mac App Store からインストールする。

起動後、メニューバーの Tailscale アイコンから **Log in** を選択してアカウント認証する。

## 13. macOS Sharing Settings (Optional)

必要に応じて **システム設定 > 一般 > 共有** を開き、以下を有効にする:

| 項目 | 用途 |
|------|------|
| 画面共有 | 別の Mac や VNC クライアントから画面を操作 |
| リモートログイン | SSH でこの Mac に接続（`ssh user@hostname.local`） |
| ファイル共有 | SMB / AFP でファイルを共有 |

Tailscale 経由でアクセスする場合は、ファイアウォールの例外設定が不要なことが多い。

## Reference: What make install-macos Does

| ステップ | 内容 |
|---------|------|
| Prezto setup | 未導入なら `~/.zprezto` へ clone、既存環境ではサブモジュールを整合 |
| `make install` | Unix向けシンボリックリンクをホームへ展開 |
| LaunchAgent setup | `dots check`をログイン時と1時間ごとに実行し、状態変化時だけ通知 |
| Zellij setup | 互換性を確認した固定版を `~/.local/bin/zellij` へインストール |
| private setup | `dotfiles-private/setup.sh` を適用（`make private` 済みの場合） |
| `macos/defaults.sh` | macOS システム設定（Dock・Finder・キーボード等） |
| `dots brew apply` | Brewfileとの差分パッケージをインストール |
| `dots dock apply` | Dock アプリ・Finder サイドバーを設定 |
