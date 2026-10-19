# Development Workflow Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## Project Home

Git リポジトリで開発作業（調査・変更・Issue/PR 対応）を始めるときは、`obsidian-project-home` が使えるなら `obsidian-project-home --repo <repository-root>` で Project Home を解決する。
終了コード `0`（一意）の場合だけ、その Current state・Next actions・Decisions・Open questions を読んでから着手する。
`session-handoff` が Project Home に残した現在地を、次のセッションが拾うための読み込み側の規約。

- 終了コード `3`（なし）・`4`（重複）・`5`（不正）、コマンド未導入、vault 未取得の場合は、本文検索による推測・新規作成をせず、そのまま進める（報告は必要な場合だけ）。
  開始時の解決は読み取り専用で、作成しない
- 対応する Project Home がない新規リポジトリは、作業のあと `session-handoff` の中で `obsidian-project-home ensure --repo <repository-root>` を使って作る。
  作成が許されるのは resolver 設定の `auto_create_owners` に挙げたオーナー（`y-marui`、`fukami-lab-sot`）のリポジトリだけで、他者のリポジトリには作らない。
  作られるのは雛形（未記入）なので、`session-handoff` が内容を埋める。
  作成しても commit・push はしない
- Project Home は要約と判断の記録であり、技術的な正本はリポジトリの docs と Issue。
  食い違う場合はリポジトリ側を正とし、Project Home の古い記述は指摘する
- 読み取りだけで、vault の変更や commit は伴わない。
  ユーザーの依頼と無関係な Project を読み込まない（解決できた対象リポジトリのものだけ）

## Fetch Before Starting Work

`git fetch` はワーキングツリーを変更しない読み取り専用操作なので、dirty な状態でも常時実行できる。
ローカルが古いベースのままコミットすると、後から origin と diverge して余計なマージ作業が発生する。
取り込んだ結果を `git pull` や `git merge` で反映するかどうかは、ワーキングツリーを変更する操作なので、clean かつユーザーの変更を壊さないことを確認してから行う。

## Scope-Based PR Requirement

- **現在のブランチで進めてよい**: memory/コンテキストの移管、Brewfile 等の依存関係定義ファイルの追従的な更新、typo 修正等の小さな変更、既存ドキュメント・skill の軽微な更新
- **PR 経由にする**: 新規スクリプトの追加、新規 skill の追加や既存 skill の大規模改修、プロジェクトの全体構造（AI コンテキスト階層等）に関わる refactoring。
  認証・データ削除・公開 API 等、変更量が小さくても影響が大きい、または復旧が難しい変更

ユーザーから commit を指示され、既読のプロジェクト指示に明示的な禁止がない場合は、現在のブランチで通常どおり commit を試みる。
pre-commit 等のフックが commit を拒否したら回避せずに理由を確認し、その時点で作業ブランチへの移動等を判断する。
規模・影響・復旧の難しさを確認しても判断できない場合はユーザーに確認する。
プロジェクトの AI_CONTEXT.md/CLAUDE.md がこの既定と異なる基準を明記している場合はそちらに従う。

## Draft PRs and Redundant CI Runs

PR を開いた後の push ごとに CI が走る。
高額ランナー（macOS 等）の課金や待ち時間を無駄にしないため、次のように運用する。
draft の間は CI が走らない（`ready_for_review` で 1 回走る）。

- AI が作る PR は、最初から draft で開く。
  ローカルで lint・test・build を通してから ready にする
- PR の作成後にバグや仕様変更が判明したら、PR を draft に戻して修正し、揃ってから ready にする
- レビュー指摘への対応は、複数のコミットをまとめてから push する（指摘ごとに push しない）
- 自動レビュー（`@codex review`、`@copilot review`）は draft の PR でも動くため、依頼のためだけに ready にしない

詳細は dev-charter の `topics/CI_POLICY-full.md`（Draft PRs・Runner Billing）を参照する。

## Documentation and Task Management

- 完成後も参照する設計判断、仕様、運用手順、確認方法、復旧・rollback、長期間有効な制約は、リポジトリの `docs/`、README、AI_CONTEXT 等の恒久ドキュメントに記録する
- TODO、進捗、担当、期限、ブロッカー、調査途中の仮説、実装チェックリスト等、完了後に不要になる情報は、GitHub Issue・sub-issue・Project（または同等のタスク管理機能）で管理する
- 一時的なローカル作業メモは Git 管理外または gitignore 対象に置いてよい。
  コミット・push はしない。
  記録先の規則自体は Issue 等の作成・更新権限を与えない。
  課題登録・管理が依頼範囲に含まれる場合に外部へ記録し、それ以外は必要な Issue 案を回答に含める
- タスク中に確定した知識は、利用者への影響・再利用の見込み・復旧上の重要性のいずれかがあり、将来も参照する場合に恒久ドキュメントへ要点を昇格する。
  変更作業が依頼範囲に含まれる場合は同じ作業内で記録し、調査・説明のみの依頼では記録案を回答に含める。
  docs と Issue へ同じチェックリストや進捗を重複させない
- 公開リポジトリの Issue・Project・docs には、秘密情報に加えて、ホスト名、IP アドレス、鍵情報、詳細なサービス構成等、不要な運用情報も掲載しない

## Coding Style

- シェルスクリプト: 対応するシェルでは ShellCheck 準拠。
  `set -euo pipefail` を基本とし、指定シェルが未対応のオプションは使わない
- Swift: SwiftLint 準拠
- Python: ruff / black 準拠。
  新規プロジェクトの最低サポートバージョンは 3.11 以上を基準とする（3.11 の EOL は 2027-10-24。近づいたら基準の引き上げを検討する）
- ハードコードされたパスを避ける（`$HOME` を使う）
- 対話コマンドは実行環境のシェルに、スクリプトは shebang で指定したシェルに合わせる。
  zsh / bash 両対応は必要な成果物だけに限定する
- 依存関係は必要に応じて既存 lockfile に基づき同期・インストールする。
  バージョン更新（`uv sync --upgrade`、`npm update` 等）は、依頼された保守作業か、タスク遂行に更新が必要な具体的根拠がある場合に限定する

## Concise Command Output

ビルド・テスト・lint・pre-commit など出力が多いコマンドは、利用可能なら `run-quiet` でラップする。
未導入の場合、親シェルの関数に依存する場合、詳細ログや進捗表示が必要な場合は直接実行してよい。
終了コードと、表示された警告・エラーを確認する。
`run-quiet` は成功時の通常出力を保存せず、警告の抜粋もすべての書式を拾うとは限らない。
詳細確認が必要な処理は初回からログを残す。
再実行が安全な検証コマンドに限り、診断情報が不足したら直接実行で再確認する。
commit・push など副作用のある操作は出力確認だけを目的に再実行しない。
特にシェル関数の Git ガードに依存する場合、外部スクリプトの `run-quiet` を通さず実行する。
どの実行経路でもフック回避禁止は維持する。
