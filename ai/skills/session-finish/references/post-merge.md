# Post-merge: 実機・環境への反映

mainへのmerge後に、成果物をユーザーの実機や環境へ反映する手順。`session-finish`のStep 5で読む。`session-handoff`では実行しない（作業を続ける途中で実機を更新しないため）。

## Choosing the command

1. プロジェクトの`AI_CONTEXT.md`・`DEVELOPING.md`・`README.md`に「Post-merge」等で宣言されたコマンドがあれば、それを使う。宣言は次の形で書く。
   - コマンド（例: `make deploy`）
   - 反映先（例: Mac実機、iOS実機、Chrome拡張、デスクトップアプリ）
   - 実行条件（例: Swift関連のパスが変わったときだけ）
2. 宣言がなければ、`Makefile`のターゲットから、プロジェクトの種類に合う次のものだけを候補にする。
   - Swift・Apple系アプリ: `make deploy`（Macアプリ）、`make ios`（iOS実機）
   - Chrome拡張: `make build`
   - Tauri系アプリ: `make deploy`
   - その他、実機・環境への反映が必要と判断できるもの（ターゲット名と種類が明確に対応する場合だけ）
3. 候補が複数あり、どれを使うか判断がつかない場合や、ターゲットが見つからない場合は、実行せずに報告する。宣言の追記をIssueまたはdocsに提案する。

## Conditions

- 最新のmainで実行する（mainを更新し、cleanであることを確認してから）。
- 最後のmergeの後に同じコマンドを実行済みで、mainのコミットIDが変わっていないときは省略する。実行済みかどうかは、会話の記録と`git rev-parse HEAD`で判断する。判断できなければ実行する。
- 今回のmergeがその反映先に影響しない変更だけ（docs・skillのみ等）の場合は省略し、省略した理由を報告する。
- 実機への反映は、ビルドと転送だけを行う。署名・公開（App Store Connect提出、Chrome Web Store公開など）は含めない。
- 失敗したら再実行を重ねず、失敗したステップの出力だけを読んで報告する。

## Report

実行したコマンド、反映先、結果。省略した場合はその理由。実行できなかった場合は、手動で行う場合の手順。
