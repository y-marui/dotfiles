@~/.ai/AI_CONTEXT.md
@~/.ai/AI_CONTEXT_CLI.md

## Running Build/Test Commands

ビルド・テスト・lint・pre-commit など出力が多いコマンドは `run-quiet` でラップして実行する。
エラーがなければ1行サマリーのみ出力され、コンテキストを節約できる。
warning/deprecated/note 行は自動的に抜粋表示される。

```sh
run-quiet make build
run-quiet swift build
run-quiet npm test
run-quiet pre-commit run --all-files
run-quiet git add <files>
run-quiet git checkout <branch>
run-quiet git commit -m "..."
# チェーンする場合は各コマンドを個別にラップする
run-quiet git add <files> && run-quiet git commit -m "..."
```

warning やエラーの情報が不足していて原因を特定できない場合は、
`run-quiet` を外してフル出力で再実行することをユーザーに提案する。

```sh
# フル出力で再実行
pre-commit run --all-files
make build
```

## Adding MCP Servers

`claude mcp add` で特定プロジェクトに紐付かない個人の恒常的なツール連携（Codex・GitHub 等）を追加する場合は、
デフォルトの local scope ではなく `-s user` を付けて登録する。

```sh
claude mcp add -s user <name> -- <command>
claude mcp add -s user --transport http <name> <url>
```

local scope のままだと、そのプロジェクトディレクトリでしか有効にならない。
なお `~/.claude.json`（MCP サーバー登録）や `~/.claude/plugins` はディレクトリ全体を
シンボリックリンク管理しない。`~/.claude/skills` も root 全体は所有せず、dotfiles 管理対象の
共通・Claude Code 専用 skill だけをディレクトリ単位でリンクする。
