# Cloud session environment

このファイルは Claude Code のクラウドセッションでだけ読み込まれる補足規約である。
`scripts/cloud-bootstrap.sh` が `~/.claude/rules/` へリンクする。

## Obsidian vault

- vault は `$OBSIDIAN_VAULT_ROOT`（既定: `~/src/github.com/y-marui/obsidian-vault`）へ clone される。
  変数が未設定、またはディレクトリが無い場合、vault は取得できていない。推測で作成せず、その旨を報告する。
- クラウドからの vault への書き込みは、`ai/cloud/<日付>-<短い主題>` ブランチへの push だけにする。
  `main` へ直接 push しない。main への統合は、ローカルで `session-finish` を使って行う。
- vault は起動時に読み取り専用の認証で clone されるため、そのままでは push できない
  （Git プロキシが認証情報を付けない）。書き込む前に `add_repo` で `y-marui/obsidian-vault` を
  `access: push` でセッションに追加し、上記の clone（`$OBSIDIAN_VAULT_ROOT`）から push する。
  別の clone は作らない。

## Available skills

- クラウドで使える skill は `ai/skills/cloud-code.json` に載るものだけである。
  ブラウザ操作・ローカルファイル・ローカル専用 MCP に依存する skill は展開されない。

## Credentials

- `DOTFILES_PRIVATE_TOKEN` と `VAULT_TOKEN` は環境変数名であり、値を表示・記録・コミットしない。
