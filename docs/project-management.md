# Project Management

dotfilesで完成後も残す知識と、開発中だけ必要なタスク情報の責務境界を定める。

## Responsibility Boundaries

| 管理先 | 内容 |
|---|---|
| `docs/`、README、AI_CONTEXT | 確定した設計判断、仕様、運用、確認、復旧、rollback、長期間有効な制約 |
| GitHub Issue | 目的、受け入れ条件、調査、ブロッカー、実装チェックリスト |
| GitHub sub-issue | 親Issueを完了可能な作業単位へ分割したもの |
| GitHub Project | Status、Priority、Area、Start date、Target date、Roadmap |
| ローカル作業領域 | ログ、下書き、検証出力等、共有も保存も不要な一時ファイル |

GitHub上のタスク情報と恒久ドキュメントに同じ進捗やチェックリストを重複させない。

## Lifecycle

1. 実装前にIssueを検索し、重複がなければ目的と完了条件を持つIssueを作る
2. 複数の独立した完了条件がある場合はsub-issueへ分割する
3. 担当、優先度、期間、進捗はGitHub Projectで管理する
4. タスク中に確定し、完成後も必要な知識は同じ作業内で `docs/` 等へ要点を昇格する
5. 恒久ドキュメントと実装の整合性を確認してからIssueを閉じる
6. 完了後に不要な計画・ログ・チェックリストはrepoへ移さない

## Public Repository Boundary

このリポジトリは公開されている。Issue、Project、docsにはシークレットを記載しない。また、公開に
不要なホスト名、IPアドレス、公開鍵指紋、実機の詳細なサービス一覧、内部ネットワーク構成も
記載しない。必要な実機情報はローカルで確認し、公開側には一般化した設計判断と検証結果だけを残す。

## Source and Synchronization

この運用は `y-marui/dev-charter` の以下の文書から必要部分だけを選択的に引用・一般化している。

- [`DOCS_STRUCTURE.md`](https://github.com/y-marui/dev-charter/blob/main/DOCS_STRUCTURE.md):
  docsを人間・AI共用のナレッジベースとして維持する
- [`PRINCIPLES.md`](https://github.com/y-marui/dev-charter/blob/main/PRINCIPLES.md):
  TODO/FIXMEは実装するかIssueとして記録する
- [`AI_CONTEXT_HIERARCHY.md`](https://github.com/y-marui/dev-charter/blob/main/AI_CONTEXT_HIERARCHY.md):
  Issue・Pull Requestのタスク文脈をプロジェクト文書より優先する
- [`topics/GITHUB_SETTINGS.md`](https://github.com/y-marui/dev-charter/blob/main/topics/GITHUB_SETTINGS.md):
  GitHub上の設定とIssue自動アサイン

dev-charterのsubtree導入やfull適用は行わない。引用元の関連ファイルが変更されたとき、このrepoの
文書・タスク運用を変更するとき、または活発な開発中は少なくとも四半期ごとに整合性を確認する。
差分があってもfull適用へ拡張せず、このrepoとグローバルAI指示に必要な変更だけを反映する。
