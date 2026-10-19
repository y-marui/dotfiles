@~/.ai/AI_CONTEXT.md
@~/.ai/AI_CONTEXT_CLI.md

<!--
  AI_CONTEXT.md 本来の Context Routing はターミナル・Git/GitHub 操作等を
  行う場合にのみ AI_CONTEXT_CLI.md を読む設計だが、Claude Code のセッションは
  ほぼ常にその条件に該当するため、ここで無条件に import して読み忘れを防ぐ。
  （実例: 2026-09 に GitHub PR 作成時、この読み込みをせず @codex review の
  コメント要否・assignee 設定を見落とした）
-->

## Adding MCP Servers

`claude mcp add` で user scope の MCP サーバーを追加する場合は、`-s user` を付けて登録する。

~~~sh
claude mcp add -s user <name> -- <command>
claude mcp add -s user --transport http <name> <url>
~~~

なお `~/.claude.json`（MCP サーバー登録）や `~/.claude/plugins` はディレクトリ全体を
シンボリックリンク管理しない。`~/.claude/skills` も root 全体は所有せず、dotfiles 管理対象の
共通・Claude Code 専用 skill だけをディレクトリ単位でリンクする。

## Delegating Large Work to Sub-sessions

大きな変更（複数の issue の解消、複数の PR になる実装、設計に影響するデータ形式の変更）は、
メインセッションでは調査・計画・方針の決定・issue の起票・サブセッションの報告の確認・merge・
記録だけを行い、実装はサブセッションに移管する。メインの使用コンテキストを約 150k 以内に抑える。
小さな変更は、メインでそのまま行う。

- 移管する前に、方針と受け入れ条件を、issue（起票がユーザーに許可されている場合）または
  サブセッションへの指示に書く。issue があれば番号を渡す
- サブセッションは、分岐（fork）ではなく新規（fresh）で始める。分岐は会話全体を引き継ぎ、
  コンテキストを小さく保つ目的に反する。必要な情報は、issue と依頼文に自己完結で書く
  （目的、対象のファイル、決定済みの事項、完了の条件、報告の形式）
- サブセッションが行う範囲は、ユーザーが許可したものに限る。commit・push・PR の作成は、
  許可があるときだけ行い（`AI_CONTEXT_CLI.md` の規約に従う）、許可がなければ、ローカルの
  変更と報告までにとどめる。許可がある場合は、レビュー指摘の対応と CI の確認まで行う。
  merge はしない
- 恒久的に残す内容は、サブセッションが同じ PR の docs に書く
- `session-finish` はメインセッションだけで実行する。サブセッションでは実行しない
- サブセッションは、最後に次を報告する: PR のリンク、設計上の判断、問題点・未解決の点、
  Project Home に残すべき知識（やってみて分かったこと）
- メインは報告を確認し、Project Home と issue に反映してから merge する

## Context Compaction

メインセッションの使用コンテキストが約 100k を超えたら、次の切れ目（PR の merge、
サブセッションへの移管、フェーズの終わり）でユーザーに `/compact` を提案する。
約 150k を超えたら、作業の途中でも提案する。ただし、変更がコミット済みで、現状が
PR・issue・計画に書かれ、テストが通っている状態にしてから提案する。未コミットの
編集、調査中の仮説、衝突解消・マージの途中では提案せず、先に状態を残す。
提案には、圧縮後に再開するための現状と次の作業を短く添える。
