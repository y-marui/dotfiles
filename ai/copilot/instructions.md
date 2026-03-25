# GitHub Copilot CLI — Global Instructions

## コーディングスタイル

- シェルスクリプト: ShellCheck 準拠、`set -euo pipefail` を先頭に書く
- Python: ruff / black 準拠
- Swift: SwiftLint 準拠
- ハードコードされたパスを避ける（`$HOME` を使う）
- zshを優先しつつbash互換を維持する

## セキュリティ

- APIキー・パスワード・トークンをコードに書かない
- シークレットをコミットしない

## 基本方針

- 変更前に影響範囲を確認する
- 不明点はユーザーに確認する

## コミット

- ユーザーから明示的に指示された時だけコミットする
- Conventional Commits形式: `feat:` / `fix:` / `chore:` / `docs:` / `refactor:`
