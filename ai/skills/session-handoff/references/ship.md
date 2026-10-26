# Ship: 区切りのついた作業をmainへ反映する

`session-handoff`と`session-finish`が共通で使う手順。「このセッションの、区切りのついた作業単位」だけをremoteとmainに反映する。呼び出し元のskillが、このセッションでの`/session-handoff`・`/session-finish`の呼び出しを、ここに書く操作の承認として扱う。

## Authorization

承認に含める操作は次のとおり。

- このセッションの変更範囲のcommitと、ブランチのpush
- このセッションが作った、または作業対象としたPRの作成（最初はdraft）、ready化、merge commitによるmerge
- merge後のローカルmainの更新（fast-forwardのみ）

次は含めず、必要になった時点で止めて報告する。

- squash・rebase merge、force push、フックの回避（`--no-verify`等）
- 自分のものでないPR、ユーザーの変更でない既存の未コミット差分
- ブランチ保護を回避するmerge（`--admin`等）。保護で拒否されたら止める

## Identifying work units

- 区切りがついた単位: 目的の変更が完結し、ローカル検証が通り、このセッションの意図したdiffだけで構成されるブランチ・PR。mergeまで進める。
- 未完了の単位: 途中の変更。作業ブランチへpushまでにとどめ、mergeしない。再開点（ブランチ・PR番号）を報告に書く。
- 判断がつかない単位は未完了として扱う。

## Procedure

`sub`は手順5（CIの確認）までで止め、mergeしない。mergeは報告を確認した`main`が行う。mainが子のPRをmergeする場合も、手順6の安全条件を満たすときだけ行う。

1. `git fetch`し、状態（変更の混在、リモートとのdivergence）を確認する。混在・divergenceがあれば、その単位を止めて報告し、他の単位は続ける。
2. `.github/workflows/`から変更に関連するlint・build・testを選び、ローカルで実行する。Markdownを変更したなら`doc-lint`も実行する。実行できない検証は理由と未確認範囲を報告する。
3. 今回変更したファイルだけを明示してstageし、Conventional Commitsでcommitしてpushする。PR経由が必要な規模なら作業ブランチ上で行う（保護対象のブランチにいる場合はブランチを切る）。
4. PRが必要で未作成なら、`.github/`のテンプレートに従ってdraftで作成する（GitHub MCP、不可なら`gh`）。本文の関連Issueは`Fixes #`・`Refs #`でリンクする。
5. ローカル検証が済んだらreadyにする。CIは完了と結果の確認だけを行い、成功ならログを読まず、失敗したときだけ失敗したジョブのログを読む。
6. 次の安全条件がすべて満たされるときだけmergeする。
   - CIが緑（必須チェックがすべて成功）
   - レビュー指摘が解決済み（妥当なものは修正済み、却下分は理由を返信して解決済み）
   - mergeable（コンフリクトなし。あれば`rebase`でなくmainをmergeして解消し、再検証する）
   - 対象が自分のPR
7. merge commitでmergeする。PRのbase以外のブランチを巻き込まない。
8. mergeしたら、ローカルのmainを`git pull --ff-only`で更新する（作業ツリーがcleanなときだけ）。

条件を満たさない単位は、mergeせずに理由・PR番号・次の一手を報告する。

## Output

実施した項目（commit、push、PR作成、ready化、merge）と、止めた項目を単位ごとに分けて返す。最後にmergeした時刻とmain上のコミットIDを返し、`post-merge.md`の「実行済み」の判定に使えるようにする。
