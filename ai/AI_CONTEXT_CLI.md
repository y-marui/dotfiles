# AI Instructions for CLI and Coding Work

## Scope

`AI_CONTEXT.md` を先に読み、次のいずれかを行う場合にこのファイルを全文読む。

- ターミナルまたはシェルを使う
- コードや管理対象ファイルを作成・変更する
- Git リポジトリ、GitHub の Issue・PR・Actions を扱う
- build・test・lint・依存関係・ツール設定を扱う
- その他の開発作業を行う

コマンド出力・シェルの規約は、プロジェクトレスの調査や個人ファイル操作を含む
すべてのターミナル操作に適用する。Git・GitHub・コーディングの規約は該当する作業にだけ適用する。
通常の会話、説明、文章作成、開発に関係しない調査には適用しない。
矛盾時は `AI_CONTEXT.md` を優先する。

## Safety for Coding and Repositories

シークレット・認証情報をコードや管理対象ファイルに書かない。
`git commit`/`push` 等で `--no-verify`（`commit` の `-n` 含む）は使わない。
pre-commit フックのエラーは無視・回避せず原因を修正する
（shell では git wrapper 関数（`dotfiles/shell/zshrc`）で技術的にも禁止済みだが、
フルパス実行や IDE 統合はこれを回避し得るため、指示としても明記する）。

## Chat and Work Directory

大規模な開発を含む作業は、1 chat につき 1 作業ディレクトリ（リポジトリ）を原則とする。
並列で進める作業や、軽微な派生タスクの場合はこの限りでない。
別のリポジトリで大規模な作業が必要になったら、その chat の作業として抱え込まず、
必要な情報を Issue に移して別 chat で進める（引き継ぎには `session-handoff` を使う）。

## Commit and Push Authorization

ユーザーから明示的に指示された時だけコミットする。作業完了後に自動でコミットしない。
commit と push は別の操作として扱い、commit の依頼だけでは push しない。
「push して」「PR を作成して」など、リモートへの反映を含む依頼がある場合に push する。

## Concise Command Output

ビルド・テスト・lint・pre-commit など出力が多いコマンドは、利用可能なら `run-quiet` で
ラップする。未導入の場合、親シェルの関数に依存する場合、詳細ログや進捗表示が必要な場合は
直接実行してよい。終了コードと、表示された警告・エラーを確認する。
`run-quiet` は成功時の通常出力を保存せず、警告の抜粋もすべての書式を拾うとは限らない。
詳細確認が必要な処理は初回からログを残す。再実行が安全な検証コマンドに限り、
診断情報が不足したら直接実行で再確認する。
commit・push など副作用のある操作は出力確認だけを目的に再実行しない。
特にシェル関数の Git ガードに依存する場合、外部スクリプトの `run-quiet` を通さず実行する。
どの実行経路でもフック回避禁止は維持する。

## Fetch Before Starting Work

git リポジトリでコード変更を伴うタスクに着手する前は、ブランチの保護有無やリポジトリの
push ポリシーに関わらず、常に `git fetch` でリモートの最新状態を取り込んでからにする
（ワーキングツリーを変更しない読み取り専用操作なので dirty な状態でも常時実行できる）。
ローカルが古いベースのままコミットすると、後から origin と diverge して余計なマージ
作業が発生するため（実際に発生した事例あり）。

取り込んだ結果を実際に `git pull` や `git merge` で取り込むかどうかは、ワーキングツリーを
変更する操作なので、clean かつユーザーの変更を壊さないことを確認してから行う。

## Scope-Based PR Requirement

作業ブランチを作成するのは、変更規模・影響・復旧の難しさから PR レビューが必要な場合とする。
それ以外は現在のブランチで作業し、clean な `main` にいることだけを理由にブランチを作成しない。

- **現在のブランチで進めてよい**: memory/コンテキストの移管、Brewfile 等の依存関係定義
  ファイルの追従的な更新、typo 修正等の小さな変更、既存ドキュメント・skill の軽微な更新
- **PR 経由にする**: 新規スクリプトの追加、新規 skill の追加や既存 skill の大規模改修、
  プロジェクトの全体構造（AI コンテキスト階層等）に関わる refactoring。
  認証・データ削除・公開 API 等、変更量が小さくても影響が大きい、または復旧が難しい変更

ユーザーから commit を指示され、既読のプロジェクト指示に明示的な禁止がない場合は、
現在のブランチで通常どおり commit を試みる。pre-commit 等のフックが commit を拒否したら
回避せずに理由を確認し、その時点で作業ブランチへの移動等を判断する。

規模・影響・復旧の難しさを確認しても判断できない場合はユーザーに確認する。プロジェクトの
AI_CONTEXT.md/CLAUDE.md がこの既定と異なる基準を明記している場合はそちらに従う。

## Local CI Checks Before Creating a PR or Pushing

PR を作成する前、またはブランチに push する前に、そのプロジェクトの CI 設定
（`.github/workflows/`）を確認し、変更に関連する lint・build・test をローカルで実行する。
文書だけの変更は文書 lint・リンク検査等、コード変更は影響する build・test を対象とする。
リポジトリ固有の必須チェックは優先する。実行できない検証は理由と未確認範囲を報告する。

## Documentation and Task Management

- 完成後も参照する設計判断、仕様、運用手順、確認方法、復旧・rollback、長期間有効な
  制約は、リポジトリの `docs/`、README、AI_CONTEXT 等の恒久ドキュメントに記録する
- TODO、進捗、担当、期限、ブロッカー、調査途中の仮説、実装チェックリスト等、完了後に
  不要になる情報は、GitHub Issue・sub-issue・Project（または同等のタスク管理機能）で管理する
- 一時的なローカル作業メモは Git 管理外または gitignore 対象に置いてよい。
  コミット・push はしない。記録先の規則自体は Issue 等の作成・更新権限を与えない。
  課題登録・管理が依頼範囲に含まれる場合に外部へ記録し、それ以外は必要な Issue 案を回答に含める
- タスク中に確定した知識は、利用者への影響・再利用の見込み・復旧上の重要性の
  いずれかがあり、将来も参照する場合に恒久ドキュメントへ要点を昇格する。
  変更作業が依頼範囲に含まれる場合は同じ作業内で記録し、調査・説明のみの依頼では
  記録案を回答に含める。docs と Issue へ同じチェックリストや進捗を重複させない
- 公開リポジトリのIssue・Project・docsには、秘密情報に加えて、ホスト名、IPアドレス、鍵情報、
  詳細なサービス構成等、不要な運用情報も掲載しない

この節は `y-marui/dev-charter` の
[`DOCS_STRUCTURE.md`](https://github.com/y-marui/dev-charter/blob/main/DOCS_STRUCTURE.md)、
[`PRINCIPLES.md`](https://github.com/y-marui/dev-charter/blob/main/PRINCIPLES.md)、
[`AI_CONTEXT_HIERARCHY.md`](https://github.com/y-marui/dev-charter/blob/main/AI_CONTEXT_HIERARCHY.md)、
[`topics/GITHUB_SETTINGS.md`](https://github.com/y-marui/dev-charter/blob/main/topics/GITHUB_SETTINGS.md)
から必要部分だけを選択的に引用・一般化したもので、dev-charterのfull適用ではない。
引用元の関連ファイルの変更を把握したとき、関連する文書・タスク運用を変更するとき、
またはユーザーが規約レビューを依頼したときに整合性を確認し、必要な差分だけを反映する。
定期レビューを設ける場合は、別途依頼された定期タスクとして管理する。

## Coding Style

- シェルスクリプト: 対応するシェルでは ShellCheck 準拠。
  `set -euo pipefail` を基本とし、指定シェルが未対応のオプションは使わない
- Swift: SwiftLint 準拠
- Python: ruff / black 準拠。新規プロジェクトの最低サポートバージョンは 3.11 以上を基準とする
  （3.11 の EOL は 2027-10-24。近づいたら基準の引き上げを検討する）
- ハードコードされたパスを避ける（`$HOME` を使う）
- 対話コマンドは実行環境のシェルに、スクリプトは shebang で指定したシェルに合わせる。
  zsh / bash 両対応は必要な成果物だけに限定する
- 依存関係は必要に応じて既存 lockfile に基づき同期・インストールする。
  バージョン更新（`uv sync --upgrade`、`npm update` 等）は、依頼された保守作業か、
  タスク遂行に更新が必要な具体的根拠がある場合に限定する

## GitHub

PR・Issue・Feature Request を作成する場合は、事前に `.github/` ディレクトリを確認し、
テンプレート（`PULL_REQUEST_TEMPLATE.md`、`ISSUE_TEMPLATE/`）があればその形式に従う。

- PR・Issue の操作は GitHub MCP サーバーを優先し、使えない場合は `gh` CLI を使う。
  いずれも Web UI から直接作成・更新・マージしない（`AI_CONTEXT.md` の Tool Selection 参照）
- `gh` が未認証の場合は、Web UI に切り替えず `gh auth login -h github.com` をユーザーに案内する
- PR のマージ方法は merge commit を標準とする。ユーザーが明示した場合のみ squash merge または rebase merge を使用する
- 関連する issue がある場合、PR 本文に `Fixes #123`/`Closes #123`（マージ時に自動クローズしたい場合）または `Refs #123`（クローズせず関連付けのみの場合）等のキーワードでリンクする
- PR ブランチのコンフリクト解消は rebase ではなく merge（base ブランチを PR ブランチにマージ）を使う。rebase は履歴を書き換え force push が必要になるため、他者が同じ PR ブランチに push している場合に問題になる。rebase は明示的に指示された場合のみ実施する
- マージ依頼には、マージ済みで未コミット変更や他の作業での使用がないブランチの整理を含める。
  マージ後は対象リポジトリと各 worktree の状態を確認し、現在のローカル tip が統合済みで、
  未 push の未統合コミットがない場合だけ整理する。upstream の消失だけで削除を判断しない。
  `git-sweep` はこれらの条件を守れる場合に使い、満たせない場合は対象を残す。
  ツールが使えない場合や整理を保留した場合は、マージの完了と分けて報告する
- GitHub Actions が課金エラーで検証を実行できない場合、コードの検証成功とはみなさない。
  ローカル等で同等の検証が完了していればマージ判断を進められる。
  代替できない検証が残る場合は、その内容を示してユーザーに判断を求める
- `y-marui/*` リポジトリで Issue・PR を作成する場合（AI が直接操作する場合・自動化コマンド経由の場合を問わない）は、見逃し防止のため assignee に `y-marui` を設定する
- GitHub Copilot の PR レビューをリクエストした場合、結果はインクリメンタルに表示されず完了時に一括で反映される。数分待たずに「反映されない＝利用不可」と結論づけない（間隔を空けてポーリングする）
- 自動レビュー（Copilot 等）の指摘は無条件に正しいものとして受け入れない。各指摘を自分で検証し、妥当と判断したものだけ修正する
- y-marui配下の全repo（および主要forkのupstream）のCI・Issue・PR状況は `y-marui/repo-status` のREADMEに一覧化されている。再生成は新規repo作成/削除・workflow構成変更時のみ `scripts/status-badges.sh` を実行する（自動更新ではなく都度手動実行）。
  private repo の Issue/PR 件数だけは、Actions の `Update private repo counts` を手動実行して更新する
  （self-hosted runner で実行。詳細は `y-marui/repo-status` の `docs/private-counts.md`）
- 新規リポジトリ名は、先頭に言語（`python-`、`swift-`、`go-`）または対象のサービス・プラットフォーム
  （`alfred-`、`chrome-`、`docker-`）を付ける。当てはまらない場合はユーザーに確認する

## Account Information

GitHub / BMC アカウントの対応表: `~/.identity/accounts.yaml`（dotfiles-private で管理）

プロジェクトの GitHub オーナーを確認し、対応する `github` / `bmc` の値を使用すること。
`make private` を実行済みであればファイルが存在する。

## Commit Messages

Conventional Commits 形式:

- `feat:`新機能
- `fix:`バグ修正
- `chore:`ビルド・設定変更
- `docs:`ドキュメント
- `refactor:`リファクタリング

## MCP Configuration Scope

個人の恒常的なツール連携は、各エージェントの user / global scope に登録する。
特定リポジトリだけで使う連携のみ project / local scope に登録する。登録コマンド、
設定ファイルの所有境界、既存設定との共存方法は、各エージェント固有の設定文書に従う。

## UI Verification for Mac/iOS Apps

Mac/iOS ネイティブアプリや Alfred Workflow の UI 検証はユーザーが行う。
該当する開発時に、[環境別手順](references/cli-environments.md#native-app-verification) を読む。

## Language for Self-Executed Issues

GitHub Issue の本文言語は、その Issue の残作業を誰が実行するかで決める。
他のコントリビューターや一般ユーザー向けの作業、あるいは一般的なプロジェクト
文書として書く場合は、そのリポジトリが定める言語ポリシー（`y-marui/*` は
原則英語）に従う。一方、実質的にユーザー自身が後で手を動かす TODO リスト
（手動セットアップ手順、実機での検証、本人しか判断できない意思決定など）で
あれば、リポジトリの言語ポリシーに関わらず本文は日本語で書く（タイトルは
どちらでもよい）。自分用のチェックリストは日本語の方が速く読めるため。

## Closed Issues: Don't Write Problem Content There

クローズ済みの GitHub Issue に、新しい問題点・調査結果・進捗を直接コメントとして
書き込まない。話題が元の Issue と近く見える場合も同様（実例: あるリポジトリで、
Issue が PR マージ直後にクローズされた後も、関連する別の不具合が見つかるたびに
そのクローズ済み Issue へ書き込み続けてしまった）。

内容を書く先は新規 Issue とする。クローズ済みの Issue 側には、必要であれば
その新規 Issue へのリンクのみを残す（内容は書かない）。この方針はリポジトリを
問わず適用する。

## Running Commands in the Warp Terminal

Warp でラッパー由来のコマンド実行エラーが起きた場合は、
[環境別手順](references/cli-environments.md#warp-command-wrappers) を読む。

## Word Splitting in zsh Loops

zsh で複数値を反復する場合は文字列の暗黙分割に頼らず、配列かリテラルを使う。
具体例が必要な場合は、[環境別手順](references/cli-environments.md#zsh-word-splitting) を読む。

## Overwriting Files in zsh

この環境の zsh は `noclobber` が有効で、`cat > file` や `echo > file` は既存ファイルの
上書きに失敗する。既存ファイルの更新は Write/Edit ツールで行い、シェルでは
`>|` を使う。失敗した heredoc 書き込みは、その後の処理が古い内容のまま
進みやすいため、書き込み後に内容を確認する。

## Interactive Prompts and Auto-ls in zsh

この環境の zsh には、Bash ツールの出力に影響する挙動が 3 つある。

- `cd` は、移動後に自動で `ls` を実行する（`dotfiles/shell/zshrc` の関数）。`cd` を含むコマンドの
  出力にディレクトリの一覧が混ざり、`grep` などの結果を読み違えやすい。ディレクトリを変えずに
  済む場合は `git -C <dir>` や絶対パスを使う
- `rm` は確認を求めることがあり（`remove <file>?`）、確認待ちのまま停止して、後続のコマンドを
  含む処理全体が止まる。非対話で削除する場合は、対象を確認したうえで `rm -f` を使う
- `cp` は `cp -i` のエイリアスで、既存ファイルの上書き時に確認を求める。非対話では
  `not overwritten` となり、終了コード 1 で上書きされない。`;` や改行で後続コマンドを続けると
  失敗を見落とし、バックアップ復元などで古い内容が残る。上書きが必要な場合は、対象を
  確認したうえで `command cp -f` を使う

## Reference Resolution

環境別手順は必要な節だけ読む。このファイルがシンボリックリンク経由の場合は、
リンクの実体である `AI_CONTEXT_CLI.md` のディレクトリを基準に `references/` を解決する。
参照先を読めない場合は、その制約を報告し、未確認の手順を推測して実行しない。
