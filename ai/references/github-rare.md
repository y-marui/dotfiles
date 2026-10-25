# GitHub Rare Procedures

`AI_CONTEXT_CLI.md` から、該当する作業時だけ参照する詳細手順。
共通規約の安全制約と commit・push の承認条件は引き続き適用する。

## gh Default Repository with SSH Host Alias

- リモートが `github-public:owner/repo` のような SSH Host エイリアス形式の場合、ユーザーの対話シェルの `gh`
  は `gh pr merge` 等で「No default remote repository has been set」を出すことがある
  （リポジトリ直下でも発生し得る）。`gh repo set-default owner/repo` の実行を案内する

## Copilot Review Latency

- GitHub Copilot の PR レビューをリクエストした場合、結果はインクリメンタルに表示されず完了時に一括で反映される。数分待たずに「反映されない＝利用不可」と結論づけない（間隔を空けてポーリングする）

## Actions Billing Errors

- private リポジトリで、ジョブが数秒で失敗し step も runner 名も付かない場合は、課金・利用上限のブロックを疑う
  （`gh api repos/<owner>/<repo>/check-runs/<id>/annotations` に "recent account payments have failed" が出る）。
  その前に、そのリポジトリがself-hostedへ移行済みか確認する：`gh variable list -R <owner>/<repo>` に
  使用OSに対応する`LINUX_RUNNER`・`MACOS_RUNNER`・`WINDOWS_RUNNER`があるか、
  `gh api repos/<owner>/<repo>/actions/runners` に runner が登録されているか。
  どちらかが欠ければ設定漏れなので、下の `New Repository Creation` の runner 手順で直す
- 変数と登録があっても、jobの`runs-on`が`ubuntu-latest`等に固定されていればhostedで動く。
  新規repoだけでなく、workflow追加・変更時も、変更判定・検証・集約gateと再利用workflowへのrunner入力を確認する。
  使用OSごとに`LINUX_RUNNER`・`MACOS_RUNNER`・`WINDOWS_RUNNER`と、対応ラベルのonline runnerを照合し、
  実ジョブのrunner名まで確認する。hostedに残すjobは理由を記録する（forkのPR、特権トークンを使う
  `pull_request_target`、OIDC releaseなど、既存の例外は維持する）。
- GitHub Actions が課金エラーで検証を実行できない場合、コードの検証成功とはみなさない。
  ローカル等で同等の検証が完了していればマージ判断を進められる。
  代替できない検証が残る場合は、その内容を示してユーザーに判断を求める

## repo-status

- y-marui配下の全repo（および主要forkのupstream）のCI・Issue・PR状況は `y-marui/repo-status` のREADMEに一覧化されている。再生成は新規repo作成/削除・workflow構成変更時のみ `scripts/status-badges.sh` を実行する（自動更新ではなく都度手動実行）。
  private repo の Issue/PR 件数だけは、Actions の `Update private repo counts` を手動実行して更新する
  （self-hosted runner で実行。詳細は `y-marui/repo-status` の `docs/private-counts.md`）

## New Repository Creation

- 新規リポジトリ名は、先頭に言語（`python-`、`swift-`、`go-`）または対象のサービス・プラットフォーム
  （`alfred-`、`chrome-`、`docker-`）を付ける。当てはまらない場合はユーザーに確認する
- 最終的に公開するリポジトリは、最初から public で作成する（`gh repo create --public`）。
  private で作ってから公開に切り替えない（公開化は権限の確認で止まり、手動の設定変更が必要になる）。
  不安定な状態が main に入るのを避けたいだけなら、private にせず `develop` 等のブランチで作業する。
  公開予定のないリポジトリは private でよい
- 新規リポジトリは、空で作らず、対応する既存のテンプレートリポジトリから作る
  （`gh repo create y-marui/<name> --template y-marui/<template> --public`。非公開は `--private`）。
  作成後に GitHub 上でテンプレートへ結び付けることはできないため、最初から使う。
  - テンプレート: Python（公開向け）は `python-package-template`、Python（非公開向け）は
    `python-closed-template`、Swift アプリは `swift-closed-template`、Chrome 拡張は
    `chrome-closed-template`、Alfred ワークフローは `alfred-workflow-template`。
    該当するテンプレートがない場合はユーザーに確認する
  - テンプレートの README の手順に従い、プレースホルダー・パッケージ名・README を置き換える
  - dev-charter は full を `docs/dev-charter` に git subtree で入れる（lite は文書のみの
    リポジトリ向け）。手順は dev-charter の `src/README-full.md` に従う
  - private リポジトリは、作成後に Linux の self-hosted runner を登録し、リポジトリ変数 `LINUX_RUNNER=linux-sh`
    を設定する（GitHub-hosted の Linux は課金対象で、無料枠を超えるとCIが起動しなくなる）。登録は
    `y-marui/docker-github-actions-runner` の `setup.sh install y-marui/<repo>`（runner ホスト上で実行）。
    登録先の台帳は非公開の dotfiles-private の `docs/self-hosted-runners.md` で、登録したら更新する。
    runner のホスト名・運用情報は公開リポジトリに書かない。public リポジトリには登録しない。
    macOS・Windowsのjobがある場合は、そのOSのrunner登録と対応する変数も設定し、上の確認手順で実ジョブを検証する。
    詳細は dev-charter の `topics/CI_POLICY.md`（Runner Billing）
  - `AI_CONTEXT.md` はテンプレートのものを、そのプロジェクト向けに書き換える。公開リポジトリには
    個人のパス・ホスト名・設定値を載せない

## Bulk PR Ready Conflicts

- 多数のリポジトリへ同じ PR を一括で出す場合、ready 化を一斉に行わない。self-hosted runner の
  共有キャッシュ（`/runner/.cache/pre-commit`）で競合し、pre-commit が `Text file busy` 等で
  失敗する（37 PR 中 11 件で発生。1 つずつ再実行すると通る）。数個ずつ時間をずらして ready にする

## Documentation Section and dev-charter

この節は `y-marui/dev-charter` の
[`DOCS_STRUCTURE.md`](https://github.com/y-marui/dev-charter/blob/main/DOCS_STRUCTURE.md)、
[`PRINCIPLES.md`](https://github.com/y-marui/dev-charter/blob/main/PRINCIPLES.md)、
[`AI_CONTEXT_HIERARCHY.md`](https://github.com/y-marui/dev-charter/blob/main/AI_CONTEXT_HIERARCHY.md)、
[`topics/GITHUB_SETTINGS.md`](https://github.com/y-marui/dev-charter/blob/main/topics/GITHUB_SETTINGS.md)
から必要部分だけを選択的に引用・一般化したもので、dev-charterのfull適用ではない。
引用元の関連ファイルの変更を把握したとき、関連する文書・タスク運用を変更するとき、
またはユーザーが規約レビューを依頼したときに整合性を確認し、必要な差分だけを反映する。
定期レビューを設ける場合は、別途依頼された定期タスクとして管理する。
