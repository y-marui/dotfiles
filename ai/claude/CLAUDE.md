# Global Claude Code Instructions

## 基本方針

- 変更前に影響範囲を確認する
- シークレット・認証情報をコードに書かない
- 不明点はユーザーに確認する

## コーディングスタイル

- シェルスクリプト: ShellCheck 準拠、`set -euo pipefail`
- Swift: SwiftLint 準拠
- Python: ruff / black 準拠

## ビルド・テストコマンドの実行

ビルド・テスト・lint など出力が多いコマンドは `build-quiet` でラップして実行する。
エラーがなければ1行サマリーのみ出力され、コンテキストを節約できる。

```sh
build-quiet make build
build-quiet swift build
build-quiet npm test
```

## コミットのタイミング

ユーザーから明示的に指示された時だけコミットする。作業完了後に自動でコミットしない。

## コミットメッセージ

Conventional Commits 形式:

- `feat:` 新機能
- `fix:` バグ修正
- `chore:` ビルド・設定変更
- `docs:` ドキュメント
- `refactor:` リファクタリング
