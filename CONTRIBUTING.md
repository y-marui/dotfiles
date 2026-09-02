# Contributing

このリポジトリは個人の dotfiles（開発環境設定）であり、外部からの積極的なコントリビューション募集は行っていない。ただし Issue・Pull Request 自体は歓迎する。

## Issue

- バグ報告・改善提案は GitHub Issues へ
- 実機固有のホスト名・IPアドレス・鍵情報・詳細なサービス構成は記載しない

## Pull Request

- ビルド・規約・テスト方法は [DEVELOPING.md](DEVELOPING.md) を参照
- コミットメッセージは Conventional Commits 形式
- `pre-commit run --all-files` を通してから提出する
- 個人運用のリポジトリのため、レビュー・マージには時間がかかることがある
- `main` は `Require conversation resolution before merging` を有効化しており（管理者にも適用）、全 conversation が resolve されるまでマージできない。返信だけでは resolve 済みにならないため、対応後に GitHub 上で明示的に resolve する。この設定は暫定であり、direct push 運用との両立方針は [y-marui/dev-charter#110](https://github.com/y-marui/dev-charter/issues/110) で検討中
