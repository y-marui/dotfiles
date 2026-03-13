# dotfiles

macOS 向け個人開発環境設定。
zsh (zprezto + Powerlevel10k) / Vim / tmux / Claude Code + GitHub Copilot。

## セットアップ（新規マシン）

```bash
# 1. リポジトリをクローン
git clone https://github.com/y-marui/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. ホスト固有設定テンプレートを生成
make init

# 3. テンプレートを編集（マシン固有の設定・パスを記入）
vi ./host/$(hostname -s).zsh

# 4. ~/.gitconfig.local を作成
cat > ~/.gitconfig.local << 'EOF'
[user]
    name = Your Name
    email = your@email.com
EOF

# 5. dotfiles をインストール
make install

# 6. 整合性確認
make check

# 7. Homebrew パッケージをインストール
make brew

# 8. macOS 設定を適用（内容を確認してから）
make macos
```

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `make install` | シンボリックリンクをホームへ展開 |
| `make uninstall` | シンボリックリンクを削除 |
| `make update` | git pull + 再インストール |
| `make check` | リンク整合性確認 |
| `make init` | ホスト固有設定テンプレートを生成 |
| `make brew` | Homebrew パッケージをインストール |
| `make macos` | macOS デフォルト設定を適用 |
| `make private` | Private Gist からプライベート設定を取得 |

## ファイル構成

| パス | 説明 |
|-----|------|
| `shell/` | zsh / bash 設定 |
| `git/` | Git 設定（公開分のみ） |
| `editor/` | Vim 設定 |
| `terminal/` | tmux / p10k 設定 |
| `ai/` | Claude Code / Copilot 設定 |
| `macos/` | Brewfile / macOS デフォルト設定 |
| `host/` | ホスト固有設定（git 管理外） |
| `scripts/` | install / check 等のスクリプト |

## プライベート設定の管理

Git の user 情報やシークレットは Private Gist で管理する。

```bash
# Gist ID を設定
cp scripts/.env.example scripts/.env
vi scripts/.env  # GIST_ID を記入

# Gist から取得
make private
```

## ローカル専用設定

マシン固有の設定は以下のファイルに書く（git 管理外）：

- `./host/$(hostname -s).zsh` — zsh のマシン固有設定
- `~/.zshrc.local` — 自動的に読み込まれる追加設定
- `~/.gitconfig.local` — Git の user 情報等
