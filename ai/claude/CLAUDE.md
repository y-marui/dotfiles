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
