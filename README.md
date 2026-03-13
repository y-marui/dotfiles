# dotfiles

macOS 向け個人開発環境設定。
zsh (zprezto + Powerlevel10k) / Vim / tmux / Claude Code + GitHub Copilot。

## セットアップ（新規マシン）

```bash
# 1. リポジトリをクローン
git clone https://github.com/y-marui/dotfiles.git ~/src/github.com/y-marui/dotfiles
cd ~/src/github.com/y-marui/dotfiles

# 2. ホスト固有設定テンプレートを生成
make init

# 3. テンプレートを編集（マシン固有の設定・パスを記入）
vi ./host/$(hostname -s).zsh

# 4. プライベート設定を取得（gitconfig.d/* / ssh/config）
cp scripts/.env.example scripts/.env
vi scripts/.env  # GIST_ID を記入
make private

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
