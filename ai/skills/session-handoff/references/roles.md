# Role: solo / main / sub

呼び出しの引数（`sub`・`main`・`solo`）を優先し、なければ`list_sessions {linked:true}`で判定する。このセッションが起動した子セッションがあれば`main`、なければ`solo`とみなす。サブセッションとして起動されたと依頼文や会話から分かる場合は`sub`とする。

| 役割 | Project Home | 反映（Step 4） | 報告 |
| --- | --- | --- | --- |
| solo | 更新する | 自分のPRをmergeまで | 通常の完了報告 |
| main | 子の報告をまとめ、1回で更新する | 自分のPRをmergeまで。子のPRがmerge済みかも確認する | 子ごとの状態も含める |
| sub | 編集しない | 自分の1つのPRをCI確認まで（mergeしない。docsはそのPRに含める。未完了はIssueへ） | 下のsub報告の形 |

`sub`は、最後に次を報告する: PRのリンク、設計上の判断、問題点・未解決の点、Project Homeに残すべき知識（やってみて分かったこと）。mainがこの報告を確認し、Project Homeを更新してからPRをmergeする。
