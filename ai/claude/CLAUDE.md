@~/.ai/AI_CONTEXT.md
@~/.ai/AI_CONTEXT_CLI.md

## Adding MCP Servers

`claude mcp add` で user scope の MCP サーバーを追加する場合は、`-s user` を付けて登録する。

~~~sh
claude mcp add -s user <name> -- <command>
claude mcp add -s user --transport http <name> <url>
~~~

なお `~/.claude.json`（MCP サーバー登録）や `~/.claude/plugins` はディレクトリ全体を
シンボリックリンク管理しない。`~/.claude/skills` も root 全体は所有せず、dotfiles 管理対象の
共通・Claude Code 専用 skill だけをディレクトリ単位でリンクする。
