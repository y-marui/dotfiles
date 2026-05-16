# macOS セットアップ手順

新規 Mac に開発環境を構築するための手順。

## 1. Homebrew をインストール

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Xcode Command Line Tools も同時にインストールされる。

**Apple Silicon (M1/M2/M3) の場合:** インストール後、新しいターミナルを開くか以下を実行して PATH を有効にする。

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## 2. SSH キーを生成・登録

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

## 3. ghq で dotfiles を取得

```bash
brew install ghq
git config --global ghq.root ~/src

ghq get https://github.com/y-marui/dotfiles.git
# → ~/src/github.com/y-marui/dotfiles/ に配置される
cd ~/src/github.com/y-marui/dotfiles
```

> SSH キーが未設定の場合は、GitHub から ZIP でダウンロードして展開しても構わない。

## 4. zprezto をインストール

zsh テーマ・補完等は zprezto に依存している。`make install` で `.zshrc` がリンクされる前にクローンしておく。

```bash
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
# ZDOTDIR を設定していない標準環境では ~/.zprezto にクローンされる
```

## 5. ホスト固有設定を生成・編集

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

## 6. プライベート設定を取得

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

## 7. dotfiles をインストール

`make install-macos` は `make private` 済みであれば `dotfiles-private/setup.sh` も自動適用する。

```bash
make install-macos
# install（シンボリックリンク）+ macos（defaults）+ brew（Brewfile）+ dock を一括適用
```

整合性を確認:

```bash
make check
```

## 8. iTerm2 Shell Integration をインストール

iTerm2 メニュー → **iTerm2 > Install Shell Integration** を実行する。

## 参考: make install-macos が行うこと

| ステップ | 内容 |
|---------|------|
| `make install` | シンボリックリンクをホームへ展開 |
| private setup | `dotfiles-private/setup.sh` を適用（`make private` 済みの場合） |
| `make macos` | macOS システム設定（Dock・Finder・キーボード等） |
| `make brew` | Brewfile のパッケージをインストール |
| `make dock` | Dock アプリ・Finder サイドバーを設定 |
