# dotfiles

macOS 向け個人開発環境設定。
zsh (zprezto + Powerlevel10k) / Vim / tmux / Claude Code + GitHub Copilot + Gemini CLI。

## セットアップ（新規マシン）

```bash
# 1. リポジトリをクローン
git clone https://github.com/y-marui/dotfiles.git /path/to/dotfiles
cd /path/to/dotfiles

# 2. ホスト固有設定テンプレートを生成
# ~/.zshrc.local と host/<hostname>.zsh が作成される
make init

# 3. テンプレートを編集（マシン固有の設定・パスを記入）
# ★ ~/dotfiles 以外にクローンした場合は ~/.zshrc.local の DOTFILES_DIR を必ず設定すること。
#    以降のすべてのコマンド（make install / brew / dock など）と
#    ログイン時の乖離チェック（brew diff / dock diff）が DOTFILES_DIR に依存する。
vi ~/.zshrc.local           # DOTFILES_DIR=/path/to/dotfiles を設定（クローン先が ~/dotfiles 以外の場合）
vi ./host/$(hostname -s).zsh

# 4. プライベート設定を取得（gitconfig.d/* / ssh/config）
cp scripts/.env.example scripts/.env
vi scripts/.env  # PRIVATE_REPO を記入（例: y-marui/dotfiles-private）
make private

# 5. dotfiles をインストール
make install          # Linux / macOS 共通（シンボリックリンクのみ）
make install-macos    # macOS 推奨（install + macos + brew + dock を一括適用）

# 6. 整合性確認
make check
```

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `make install` | シンボリックリンクをホームへ展開 |
| `make uninstall` | シンボリックリンクを削除 |
| `make update` | git pull + 再インストール |
| `make check` | リンク整合性確認 |
| `make init` | ホスト固有設定テンプレートを生成 |
| `make private` | dotfiles-private を GitHub からクローン・更新 |
| `make brew` | Brewfile を適用 |
| `make brew-sync` | 現在の Homebrew 状態を Brewfile に同期 |
| `make macos` | macOS デフォルト設定を適用 |
| `make dock` | Dock アプリ・Finder サイドバーを適用 |
| `make dock-sync` | 現在の Dock・サイドバーを dock.sh に同期 |

## ファイル構成

| パス | 説明 |
|-----|------|
| `shell/` | zsh / bash 設定 |
| `git/` | Git 設定（公開分のみ） |
| `terminal/` | tmux / p10k 設定 |
| `ai/` | Claude Code / Copilot / Gemini CLI 設定 |
| `macos/` | Brewfile / macOS デフォルト設定 |
| `host/` | ホスト固有設定（git 管理外） |
| `scripts/` | install / check 等のスクリプト |

## AI 設定

グローバル共通指示は [`ai/AI_CONTEXT.md`](ai/AI_CONTEXT.md)（→ `~/.ai/AI_CONTEXT.md`）に集約し、各エージェントのグローバル設定ファイルからインポートしている。
リポジトリ固有のコンテキストは [`AI_CONTEXT.md`](AI_CONTEXT.md) に集約し、各エージェントのリポジトリ固有ファイルから参照している。

### Claude Code

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/AI_CONTEXT.md`](ai/AI_CONTEXT.md) | `~/.ai/AI_CONTEXT.md` | 全エージェント共通グローバル指示 |
| [`ai/claude/settings.json`](ai/claude/settings.json) | `~/.claude/settings.json` | ツール許可・フック設定 |
| [`ai/claude/CLAUDE.md`](ai/claude/CLAUDE.md) | `~/.claude/CLAUDE.md` | グローバル指示（`@~/.ai/AI_CONTEXT.md` をインポート） |
| [`ai/claude/hooks/`](ai/claude/hooks/) | `~/.claude/hooks/` | タスク完了通知フック |
| [`CLAUDE.md`](CLAUDE.md) | — | リポジトリ固有指示（`@./AI_CONTEXT.md` をインポート） |

参照: [Claude Code ドキュメント](https://docs.anthropic.com/en/docs/claude-code)

### GitHub Copilot CLI

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/copilot/instructions.md`](ai/copilot/instructions.md) | `~/.copilot/copilot-instructions.md` | グローバル指示（`~/.ai/AI_CONTEXT.md` への参照のみ） |
| [`.github/copilot-instructions.md`](.github/copilot-instructions.md) | — | リポジトリ固有指示 |

参照: [Copilot CLI ベストプラクティス](https://docs.github.com/ja/copilot/how-tos/copilot-cli/cli-best-practices)

### Gemini CLI

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/gemini/GEMINI.md`](ai/gemini/GEMINI.md) | `~/.gemini/GEMINI.md` | グローバル指示（`@~/.ai/AI_CONTEXT.md` をインポート） |
| [`GEMINI.md`](GEMINI.md) | — | リポジトリ固有指示（`@./AI_CONTEXT.md` をインポート） |

参照: [GEMINI.md ドキュメント](https://geminicli.com/docs/cli/gemini-md/)

---

## Zellij 自動アタッチ・SSH ラッパー

### Zellij 自動アタッチ

以下の条件で起動時に自動的にZellijセッション（セッション名: ホスト名）にアタッチする。

- iTerm2から起動した場合
- SSHでリモートログインした場合（`$SSH_CONNECTION` が設定されている場合）

`NO_ZELLIJ=1` を設定するか、`ZELLIJ` が設定済みの場合はスキップされる。

### ssh コマンドのラッパー（iTerm2 + Zellij内のみ有効）

Zellij内で `ssh` を実行するとZellijが二重になるため、iTerm2の別ペイン/タブで開くラッパーを提供している。
接続先でもZellijが自動起動する。

| コマンド | 動作 | 接続先の Zellij |
|---------|------|----------------|
| `ssh user@host` | 現在のタブを縦分割して右ペインで接続 | 自動起動 |
| `ssh --new user@host` | "No Zellij" プロファイルの新規タブで接続 | 自動起動 |
| `ssh --no-zellij user@host` | 縦分割ペインで接続 | 起動しない |
| `ssh --new --no-zellij user@host` | 新規タブで接続 | 起動しない |

> `--new` と `--no-zellij` は独立したフラグなので併用できる。

---

## プライベート設定の管理

Git の user 情報・SSH config・Dock 設定は `dotfiles-private`（GitHub プライベートリポジトリ）で管理する。

```bash
# リポジトリを設定
cp scripts/.env.example scripts/.env
vi scripts/.env  # PRIVATE_REPO を記入（例: y-marui/dotfiles-private）

# クローン
make private
```

## ローカル専用設定

マシン固有の設定は以下のファイルに書く（git 管理外）：

- `./host/$(hostname -s).zsh` — zsh のマシン固有設定
- `~/.zshrc.local` — zsh: 自動的に読み込まれる追加設定
- `~/.bashrc.local` — bash: 自動的に読み込まれる追加設定
- `macos/Brewfile.local` — Homebrew: このマシン固有のパッケージ（`make init` で空ファイルを生成）

### Brewfile.local — マシン固有 Homebrew パッケージ

メインの `Brewfile` に含めたくない（他のマシンには入れたくない）パッケージを管理する。

```bash
# make init で凡例付き空ファイルが生成される
make init

# Brewfile.local を編集してパッケージを追加する
vi macos/Brewfile.local
```

記法は `Brewfile` と同じ:

```ruby
brew "some-work-tool"        # CLI ツール
cask "proprietary-app"       # GUI アプリ（Cask）
tap "org/tap"                # Tap
mas "App Name", id: 1234567  # Mac App Store
vscode "publisher.extension" # VS Code 拡張
```

**自動整合（`make brew-sync` 実行時）:**

| 状況 | 動作 |
|------|------|
| パッケージをシステムからアンインストールした | `Brewfile.local` からも自動除去 |
| パッケージをメインの `Brewfile` に追記した | `Brewfile.local` からも自動除去（重複防止） |

**インストール（`make brew` 実行時）:**
`Brewfile` のインストール後に `Brewfile.local` のパッケージも自動でインストールされる。

### 設定が必要な環境変数

以下の変数は `host/$(hostname -s).zsh` または `~/.zshrc.local` に設定する。

| 変数 | タイミング | 説明 |
|------|-----------|------|
| `DOTFILES_DIR` | ghq 等で `~/dotfiles` 以外にクローンした場合は**必須** | dotfiles のクローン先パス（例: `/path/to/dotfiles`）。未設定時は `~/dotfiles` が使われる |
| `HOMEBREW_GITHUB_API_TOKEN` | `brew search` 等でレート制限に当たる場合 | GitHub API への認証トークン。現在の Homebrew では必須ではないが、API 制限が頻繁に発生する場合に設定する |

---

## セキュリティ: pre-commit フック

機密情報（トークン・秘密鍵・ローカルパス等）の誤コミットを防ぐ静的解析フックを導入している。
[gitleaks](https://github.com/gitleaks/gitleaks) と [pre-commit](https://pre-commit.com/) を使用。

### 検知対象

| カテゴリ | 具体例 |
|---------|-------|
| クラウド認証情報 | AWS アクセスキー / シークレット、GCP サービスアカウントキー、Azure Storage キー |
| VCS トークン | GitHub Personal Access Token (classic / fine-grained) |
| 秘密鍵 | SSH 秘密鍵ファイル・インライン記述 |
| ローカル絶対パス | `/Users/username/`、`/home/username/`、`C:\Users\` |
| .env ファイル | `.env`、`.env.local`、`.env.production` 等（`.env.example` は許可） |
| 汎用シークレット | `password = "..."` のような直接代入 |

### セットアップ

```bash
# 1. pre-commit をインストール（Python 3.8+ が必要）
pip install pre-commit
# または Homebrew
brew install pre-commit

# 2. gitleaks をインストール（macOS）
brew install gitleaks
# または Linux
# curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/main/scripts/install.sh | sh

# 3. フックをリポジトリに登録（以降は git commit 時に自動実行）
pre-commit install

# 4. 全ファイルを対象に手動スキャン（初回確認推奨）
pre-commit run --all-files
```

### 設定ファイル

| ファイル | 説明 |
|---------|------|
| `.pre-commit-config.yaml` | フック定義（使用するツール・バージョン） |
| `.gitleaks.toml` | gitleaks カスタムルール・除外設定 |

### False Positive（誤検知）への対応

**特定ファイルをスキャン対象から除外する**

`.gitleaks.toml` の `[allowlist]` セクションに追加する:

```toml
[allowlist]
paths = [
  '''tests/fixtures/.*''',   # テスト用フィクスチャ
  '''docs/examples/.*''',    # ドキュメント例
]
```

**特定行をインラインで除外する**

コード内のコメントで 1 行だけ除外できる:

```bash
# gitleaks:allow
EXAMPLE_KEY="AKIAIOSFODNN7EXAMPLE"  # AWS 公式ドキュメントのサンプル
```

**特定コミットを除外する**

`.gitleaks.toml` の `commits` リストにハッシュを追加する:

```toml
[allowlist]
commits = [
  "abc123def456...",  # 既知の false positive が含まれるコミット
]
```

**フックを一時的にスキップする（緊急時のみ）**

```bash
# 特定フックだけスキップ
SKIP=gitleaks git commit -m "..."

# 全フックをスキップ（非推奨・緊急時のみ）
git commit --no-verify -m "..."
```

> [!CAUTION]
> `--no-verify` は緊急時以外使用しないこと。
> スキップした場合は必ず直後のコミットで修正すること。

### フックのアップデート

```bash
# 全フックを最新バージョンに更新
pre-commit autoupdate

# CI での利用（キャッシュを使って高速化）
pre-commit run --all-files --show-diff-on-failure
```
