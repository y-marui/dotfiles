# Shared agent skills

## Design Goal

`ai/skills/` の設計目標は、同じ内容の skill をできるだけ多くの agent（Claude Code、Codex、Gemini CLI など）で使い回すことである。skillを追加・移動する際は、ツール固有の機能や記法に本当に依存する内容だけを `ai/claude/skills/` や `ai/codex/skills/` などのツール固有配置へ切り出し、それ以外は極力ここへ残す。

## Writing Policy

各 `SKILL.md` は、トリガー用の frontmatter `name` / `description` とMarkdown見出しを英語で書き、本文の説明・手順・判断基準は日本語で書く。コード、パス、コマンド、実際のUI文言は変えない。UI用の `agents/openai.yaml` では、`display_name` と `short_description` を日本語で書く。

Claude Code と Codex の両方で使える skill は `ai/skills/<skill-name>/SKILL.md` として追加する。

`dots claude apply --skill-only` は `~/.claude/skills/<skill-name>`、
`dots codex apply --skill-only` は `~/.agents/skills/<skill-name>` へ、同じ実体を個別にリンクする。

ツール固有の機能や記法に依存する skill だけを `ai/claude/skills/` または
`ai/codex/skills/` に置く。共通 skill とツール固有 skill で同じ名前は使用しない。

外部・curated skillは `external.json` に `name`、`repo`、`path`、固定した `ref`、
`targets` を宣言する。`apply --skill-only` は公式skill-installerでdotfiles専用キャッシュへ
取得し、両agentから同じ実体を参照する。宣言を削除した後に両agentで
`prune --skill-only` を実行すると、管理リンクと参照されなくなったキャッシュを退避する。

## Cloud Skills

claude.aiのSkills（Capabilities）は、ローカルAgent Skillと同じ `SKILL.md` 形式で、
Bash・WebFetch・同梱`scripts/`の実行が可能なサンドボックスを持つ（例:
`weather-check` は同梱の `scripts/sunrise_sunset.py` をBash経由で実行している）。
持たないのは、GUIブラウザ操作（computer use・Claude in Chrome）と、実機のローカル
ファイル・ローカル専用MCP（`gh`・`codex` 等のCLIをラップするstdio MCPサーバー等）
への依存である。これらに依存しない `ai/skills/` skillは、そのままclaude.aiのSkillとしても
登録できる可能性が高いため、専用ディレクトリへは分岐させず、`cloud.json` で登録対象を宣言する。

`cloud.json` の各エントリ:
- `name`: `ai/skills/<name>` として存在するskill名（存在しない名前はエラー）
- `synced_hash`: 直近で正常に同期できた時点の `SKILL.md` のSHA-256。未同期なら `null`
- `scheduled_tasks`: このskillを呼び出しているclaude.aiのScheduled Task名の一覧
  （なければ空配列）。ここが非空のskillは、cloud側から切り離すとScheduled Taskが
  壊れるため、`scripts/check-cloud-skill-schedule-removal.sh`（pre-commit）が
  `cloud.json` からのエントリ削除や `synced_hash` の削除をブロックする。

登録対象は `scripts/check-skills.sh` で、computer use・Claude in Chrome・ローカル
ファイル・ローカルMCP等への言及がないかを機械的に検査する。claude.ai側にはSkill作成・
更新・読み取りの公開APIがないため、実際の反映（ローカル⇔cloud間の差分検知・反映）は
ブラウザ操作が必要になり、`ai/claude/skills/sync-cloud-skills/` が担う。

## Private Data

skill本体（判定ロジック・操作手順）は `ai/skills/`（または各ツール固有配置）に置き、
アカウント名・アカウント対応表・個人の趣味嗜好リストなど個人を特定できる情報は
skill本体に直接書かない。

- サービスのアカウント名・カレンダーIDなどのリソース識別子・ジャンル対応表など、
  固定で小規模な設定データは `dotfiles-private` に置き、`links.conf` で
  `~/.identity/<service>-*.yaml` 等の固定パスへリンクする。skillはそのパスだけを読み、
  中身のスキーマだけを前提にする（例: `bookmeter-add-want-to-read` は
  `~/.identity/bookmeter-accounts.yaml` の `genre`/`label`/`display_name` を、
  `sendaicmc-*` は `~/.identity/sendaicmc-calendars.yaml` の `key`/`label`/`calendar_id`
  や `~/.identity/sendaicmc-jimoty.yaml` の `fallback_article_url`/`fallback_edit_url`
  を、`google-maps-add-saved-place` は `~/.identity/google-maps-account.yaml` の
  `authuser` を読む）。`.example` は `dotfiles/templates/dotfiles-private/` と
  完全一致させ、`links.conf` / `links.conf.example` は dotfiles-private側の規約どおり
  完全一致させる（詳細は dotfiles-private の `docs/specification.md` / `DEVELOPING.md`）。
- 保存先リストの内容・読書ログ等、量が多い・頻繁に増減する個人データは
  `obsidian-vault` 側に置く。
- ログイン済みブラウザ状態にのみ依存し、アカウント選択や個人設定データを必要としない
  skill（例: `filmarks-add-want-to-watch`）は、私有データファイルを持たなくてよい。

## Naming

特定のサービス・アプリと連携する skill は `<service>-<verb>-<object>` の順にし、
サービス名を先頭に置く（例: `spotify-distribute-liked-songs`、`glance-task-add-museum-event`）。
関連するskill同士が名前順で並ぶようにするため。コロン区切り（`service:verb`）は
plugin skillの表記（`plugin:skill`）と紛らわしいため使わない。

特定のサービス・アプリに紐づかない汎用skill（`consolidate-global-memory`、
`docx-proofreading` 等）は、この接頭辞ルールの対象外とし、動詞や主題から始める
従来通りの命名でよい。
