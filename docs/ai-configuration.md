---
description: Claude Code・Codex・GitHub Copilot CLI の管理ファイル、dots claude/codex/copilot/ai、dots check の説明
---

# AI Configuration

`ai/` の管理方針、コンテキスト階層、ディレクトリ責務、公開・private・実行時状態の
境界、変更時の確認手順は [`ai/README.md`](../ai/README.md) を参照する。

常時読むグローバル共通指示は [`ai/AI_CONTEXT.md`](../ai/AI_CONTEXT.md)
（→ `~/.ai/AI_CONTEXT.md`）に集約し、各エージェントのグローバル設定ファイルから
インポートまたは直接リンクしている。同ファイルの Context Routing に従い、
Computer Use は [`ai/AI_CONTEXT_COMPUTER_USE.md`](../ai/AI_CONTEXT_COMPUTER_USE.md)、
CLI・Coding・リポジトリ・Git/GitHub の作業は
[`ai/AI_CONTEXT_CLI.md`](../ai/AI_CONTEXT_CLI.md) を必要時だけ読む。
使う場面が限られる環境固有の詳細は [`ai/references/`](../ai/references/) に分けてあり、
`ai/AI_CONTEXT_CLI.md` 末尾の Detail References の表に従って必要時だけ参照する。リンク経由で読む場合は、CLI 規約ファイルの実体から参照先を解決する。
リポジトリ固有のコンテキストは [`AI_CONTEXT.md`](../AI_CONTEXT.md) に集約し、各エージェントのリポジトリ固有ファイルから参照している。

## Claude Code

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/AI_CONTEXT.md`](../ai/AI_CONTEXT.md) | `~/.ai/AI_CONTEXT.md` | 全エージェント共通グローバル指示 |
| [`ai/AI_CONTEXT_COMPUTER_USE.md`](../ai/AI_CONTEXT_COMPUTER_USE.md) | `~/.ai/AI_CONTEXT_COMPUTER_USE.md` | Computer Use固有の許可・操作ルール |
| [`ai/AI_CONTEXT_CLI.md`](../ai/AI_CONTEXT_CLI.md) | `~/.ai/AI_CONTEXT_CLI.md` | CLI・Coding・リポジトリ・Git/GitHub固有の作業ルール |
| [`ai/claude/settings.json`](../ai/claude/settings.json) | `~/.claude/settings.json` | ツール許可・フック設定 |
| [`ai/claude/CLAUDE.md`](../ai/claude/CLAUDE.md) | `~/.claude/CLAUDE.md` | 共通contextをインポート（補完規約はContext Routingで参照） |
| [`ai/claude/hooks/`](../ai/claude/hooks/) | `~/.claude/hooks/` | タスク完了通知フック |
| [`ai/skills/`](../ai/skills/) | `~/.claude/skills/<skill-name>/` | Codex と共有する個人 skill |
| [`ai/claude/skills/`](../ai/claude/skills/) | `~/.claude/skills/<skill-name>/` | Claude Code 専用の個人 skill |
| [`ai/claude/mcp/`](../ai/claude/mcp/) | Claude Code user scope | MCP の宣言と実態との差分・追加 |
| [`ai/claude/plugin/`](../ai/claude/plugin/) | Claude Code user scope | marketplace / plugin の宣言と実態との差分・追加 |
| [`CLAUDE.md`](../CLAUDE.md) | — | リポジトリ固有指示（`@./AI_CONTEXT.md` をインポート） |

`dots claude {diff|apply|prune}` は MCP・plugin・skill をまとめて処理する。
`--mcp-only`、`--plugin-only`、`--skill-only` で対象を1種類に限定できる。
`apply` は追加・更新に続けて `prune` を実行して宣言と完全一致させる（`--no-prune` で追加・更新のみ）。
`prune` は未宣言の user scope MCP / plugin と dotfiles 所有の skill リンクだけを
削除またはバックアップへ退避し、単独でも実行できる。
IDE/app と local/project scope のMCPは検出するが `prune` の対象外とする。local scopeは
`~/.claude.json` 内の端末・リポジトリ固有設定、project scopeは各リポジトリの
`.mcp.json` にある共有設定として区別して表示する。

参照: [Claude Code ドキュメント](https://docs.anthropic.com/en/docs/claude-code)

仙台3館の映画推薦とGlance Taskへの映画登録は [Cinema Skills](cinema-skills.md) を参照する。

## Codex

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/codex/AGENTS.md`](../ai/codex/AGENTS.md) | `~/.codex/AGENTS.md` | 共通contextの読み込み指示（補完規約はContext Routingで参照） |
| [`ai/skills/`](../ai/skills/) | `~/.agents/skills/<skill-name>/` | Claude Code と共有する個人 skill |
| [`ai/codex/skills/`](../ai/codex/skills/) | `~/.agents/skills/<skill-name>/` | Codex 専用の個人 skill |
| [`ai/codex/mcp/`](../ai/codex/mcp/) | `~/.codex/config.toml` 内の MCP 設定 | 公式 MCP の宣言と実態との差分・追加 |
| [`ai/codex/plugin/`](../ai/codex/plugin/) | Codex の plugin 状態 | plugin の宣言と実態との差分・追加 |
| [`AGENTS.md`](../AGENTS.md) | — | リポジトリ固有指示（`AI_CONTEXT.md` を参照） |

Codex の個人 skill は現行標準の `~/.agents/skills` へ追加する。
`~/.codex/skills` も検知対象に含め、`.system` 以外は `+codex` として報告するが、
`apply` では変更しない。管理対象と同名の skill がある場合、`make install` は二重読み込みを
避けるため `~/.dotfiles-backup/<timestamp>/codex-skills/` へ退避してからリンクする。
`.system` はCodex管理のため対象外とする。外部・curated skillを共通利用する場合は
[`ai/skills/external.json`](../ai/skills/external.json) に取得元とrefを宣言し、
dotfiles専用キャッシュからClaude CodeとCodexの両方へリンクする。第三者のskill本体は
このリポジトリへvendorしない。

`dots codex {diff|apply|prune}` は MCP・plugin・skill をまとめて処理する。
Claude Code と同じく `--mcp-only`、`--plugin-only`、`--skill-only` を指定できる。
plugin は `codex app-server` の `plugin/list` が返す統合済みの実態を使うため、Codex
アプリまたは CLI から追加された local / remote plugin を検知する。remote plugin の
追加・削除には同じ app-server の `plugin/install` / `plugin/uninstall` を使用する。
ただし、remote かつ `INSTALLED_BY_DEFAULT` の plugin は Codex 管理として宣言との差分・
`apply`・`prune` の対象外にする。
skill は実際の個人 skill ディレクトリを検査する。plugin内包MCPとChatGPT/Codexアプリの
内部MCPは所有元を表示し、直接MCPの差分や`prune`対象には含めない。

追加する MCP は、公式サーバーが確認できる次の接続だけに限定する。

- Claude Code → Codex の公式 MCP server mode、GitHub Remote MCP、同 Copilot toolset
- Codex → Claude Code の公式 MCP server mode、GitHub Remote MCP、同 Copilot toolset
- Codex → Raindrop.io の公式hosted MCP（Pro向けbeta、OAuth 2.1。
  公式ヘルプ指定の `mcp-remote` bridge経由）

## Batch-Check All Agents (`dots check`)

`dots check` はシンボリックリンク、dotfilesの状態、パッケージ管理、全 AI Agent の
MCP・plugin・skill の設定差分をまとめて検査する。macOSでは、`/etc/pam.d/sudo_local`
で `pam_tid.so` が有効になっており、`sudo` から読み込まれることも読み取り専用で検査する。

macOSでは、`make install-macos` がLaunchAgentを登録し、ログイン時と1時間ごとに
`dots check`をバックグラウンド実行する。結果は`dots check`本体が
`~/.cache/dots/check-summary`へ保存し、内容が変わった場合だけシステム通知する。
zsh起動時はこのキャッシュを読むだけなので、`dots check`の完了を待たない。
LaunchAgentのplistと実行スクリプトはdotfilesで共有し、既存Macでも`dots update`時に
再リンク・再登録する。手動で`dots check`を実行した場合も同じキャッシュが更新される
ため、`dots ...`コマンドで警告を解消した直後でも次のシェル起動時の表示は最新になる。

Windowsの`dots check`もUnix版と同じ形式で警告を要約し、`~/.cache/dots/check-summary`等へ書く。
対象はシンボリックリンク、`~/.dotfiles-backup`の蓄積、dotfiles / dotfiles-privateのGit状態、`winget`・`ghq`・AI（Claude Code・Codex・Copilot）の差分で、`--verbose`で詳細を表示する。
PowerShellのprofileはシェル起動時にこのキャッシュを表示する。macOS固有の項目（brew・dock・shortcuts・sudo Touch ID）と、LaunchAgent相当の定期実行・通知は対象外で、キャッシュは`dots check`を実行したときに更新される。

Claude Code・Codex の宣言をまとめて同期する場合は
`dots ai {apply|diff|prune}` を使用する。`--mcp-only`、`--plugin-only`、
`--skill-only`、`--no-prune` は3エージェントすべてへ渡される。Copilot は管理対象が user scope MCP
のみで引数体系が異なるため、`dots ai` には含めず `dots copilot` で個別に操作する。
Windowsでも同じ `dots {ai|claude|codex|copilot}` を使える（`ai/` 配下の `*.ps1` を実行する。
macOS固有の判定（`/Applications/ChatGPT.app`）以外は同じ挙動）。skill のリンクはシンボリックリンクなので、
権限が足りなければ `gsudo` で自動的に昇格して再実行する（`gsudo` がなければ開発者モードを有効にする）。

GitHub の認証値は `apply` 時に `gh auth token` から取得する。値は公開 repo には書かず、
Claude Code は `~/.claude.json`、Codex は `~/.codex/config.toml` の静的 Authorization
ヘッダーへ保存する。これは `GITHUB_PAT_TOKEN` 環境変数や手動発行PATを必要としない。
トークンが更新された場合は `apply --mcp-only` を再実行する。
両設定ファイルは `600` とし、Claude側は `diff` で権限も検査する。
`codex mcp list --json` は静的ヘッダー値も返すため、出力をログやIssueへ貼らない。

- Copilot CLI → Claude Code / Codex の公式 MCP server mode
- Copilot CLI エージェント自体、別PCの Ollama を汎用操作する公式 MCP
  server は採用していない。独自 MCP bridge も作成しない。

`~/.codex` の次の内容も管理対象外とする。

- `auth.json`、履歴、DB、ログ、キャッシュ、端末・セッション状態
- `rules/default.rules`（端末固有パスや過去の承認を蓄積したローカル状態）
- `config.toml` 全体（プロジェクト信頼状態、アプリ固有の絶対パス等を含み、Codex が更新する）

MCP と plugin の管理ファイルは公開可能な宣言だけを保持し、`config.toml` 自体はリンクせず
各CLI経由で追加・更新・削除する。トークン値は管理対象外とする。

将来、シークレットを含む Codex 設定を再現する必要が出た場合は、公開 repo ではなく
`dotfiles-private/ai/codex/` に置き、同リポジトリの `links.conf` にリンク対応を宣言する。

参照: [Codex skills](https://learn.chatgpt.com/docs/build-skills)、[Codex MCP](https://learn.chatgpt.com/docs/extend/mcp)、[Codex plugins](https://learn.chatgpt.com/docs/build-plugins)

## GitHub Copilot CLI

| ファイル | リンク先 | 説明 |
|---------|---------|------|
| [`ai/copilot/instructions.md`](../ai/copilot/instructions.md) | `~/.copilot/copilot-instructions.md` | グローバル指示（`~/.ai/AI_CONTEXT.md` への参照のみ） |
| [`ai/copilot/mcp/`](../ai/copilot/mcp/) | `~/.copilot/mcp-config.json` 内の MCP 設定 | MCP の宣言と実態との差分・追加 |
| [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) | — | リポジトリ固有指示 |

`dots copilot {diff|apply|prune}` は Copilot CLI の user scope MCP を処理する。
workspace・plugin・builtin MCP は検出対象だが `prune` の対象外とする。

参照: [Copilot CLI ベストプラクティス](https://docs.github.com/ja/copilot/how-tos/copilot-cli/cli-best-practices)
