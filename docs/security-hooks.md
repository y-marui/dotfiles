---
description: gitleaks と pre-commit による機密情報の誤コミット防止フックの設定と運用
---

# Security: pre-commit Hooks

機密情報（トークン・秘密鍵・ローカルパス等）の誤コミットを防ぐ静的解析フックを導入している。
[gitleaks](https://github.com/gitleaks/gitleaks) と [pre-commit](https://pre-commit.com/) を使用。

## What Gets Detected

| カテゴリ | 具体例 |
|---------|-------|
| クラウド認証情報 | AWS アクセスキー / シークレット、GCP サービスアカウントキー、Azure Storage キー |
| VCS トークン | GitHub Personal Access Token (classic / fine-grained) |
| 秘密鍵 | SSH 秘密鍵ファイル・インライン記述 |
| ローカル絶対パス | `/Users/username/`、`/home/username/`、`C:\Users\` |
| .env ファイル | `.env`、`.env.local`、`.env.production` 等（`.env.example` は許可） |
| 汎用シークレット | `password = "..."` のような直接代入 |

## Setup

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

## Configuration Files

| ファイル | 説明 |
|---------|------|
| `.pre-commit-config.yaml` | フック定義（使用するツール・バージョン） |
| `.gitleaks.toml` | gitleaks カスタムルール・除外設定 |

## Handling False Positives

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

## Updating the Hooks

```bash
# 全フックを最新バージョンに更新
pre-commit autoupdate

# CI での利用（キャッシュを使って高速化）
pre-commit run --all-files --show-diff-on-failure
```
