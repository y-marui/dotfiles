# Shared agent skills

## Design Goal

`ai/skills/` の設計目標は、同じ内容の skill をできるだけ多くの agent（Claude Code、Codex など）で使い回すことである。skillを追加・移動する際は、ツール固有の機能や記法に本当に依存する内容だけを `ai/claude/skills/` や `ai/codex/skills/` などのツール固有配置へ切り出し、それ以外は極力ここへ残す。

## Writing Policy

各 `SKILL.md` は、トリガー用の frontmatter `name` / `description` とMarkdown見出しを英語で書き、本文の説明・手順・判断基準は日本語で書く。コード、パス、コマンド、実際のUI文言は変えない。すべての管理対象skillにUI用の `agents/openai.yaml` を置き、`display_name` と `short_description` を日本語で書く。

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

cloud skillが[Private Data](#private-data)パターン（`~/.identity/<name>.yaml` 等を既定値
として読む）を併用する場合は注意する。cloud実行時はそのパスへアクセスできないため、
`scheduled_tasks` が非空のskillでこれをそのまま同期すると、無人実行時に既定値が失われる。
このため、cloud側だけファイル末尾に「Private Data (cloud-only)」節を追加して実値をまとめ、
本文中の参照文言はその節を指す1文に置き換える（例: `weather-check` の地点、`morning-brief`
の複数カレンダーID一覧）。cloud側のSkill本体はアカウント個人のプライベート設定でgitに乗らない
ため、実値の保持を許容する。ローカル（`ai/skills/<name>/SKILL.md`、gitで公開管理）は
`~/.identity/<name>.yaml` への参照文言のまま保ち、末尾セクションは持たせない。この形式の
同期手順・衝突判定は `ai/claude/skills/sync-cloud-skills/`（特に「Private Data: When Local
and Cloud May Diverge」）に従う。`check-skills.sh` のcloud portabilityチェックはキーワード
一致ベースのため、この依存を機械的には検知しない。

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
  `authuser` を、`weather-check` は `~/.identity/weather-location.yaml` の
  `label`/`prefecture_code`/`area_code`/`latitude`/`longitude` を、`morning-brief` は
  `~/.identity/morning-brief-calendars.yaml` の `key`/`label`/`calendar_id` を読む）。
  `.example` は
  `dotfiles/templates/dotfiles-private/` と
  完全一致させ、`links.conf` / `links.conf.example` は dotfiles-private側の規約どおり
  完全一致させる（詳細は dotfiles-private の `docs/specification.md` / `DEVELOPING.md`）。
- 保存先リストの内容・読書ログ等、量が多い・頻繁に増減する個人データは
  `obsidian-vault` 側に置く。
- ログイン済みブラウザ状態にのみ依存し、アカウント選択や個人設定データを必要としない
  skill（例: `filmarks-add-want-to-watch`）は、私有データファイルを持たなくてよい。

## Naming

特定のサービス・アプリと連携するskillは `<service>-<verb>-<object>`、特定の団体・業務ドメインを
起点に複数サービスを扱うskillは `<domain>-<verb>-<object>` の順にする。接頭辞を先頭に置き、
関連するskill同士が名前順で並ぶようにするため。コロン区切り（`service:verb`）はplugin skillの
表記（`plugin:skill`）と紛らわしいため使わない。

サービス・業務ドメインskillの `display_name` も、`<表示用接頭辞> <動作>`（接頭辞の直後は半角
スペース1つ）で始める。表示用接頭辞は日本語の定着名を優先し、自然な日本語名がないものは英語名を
使う。汎用skillはこの接頭辞規則の対象外だが、UIメタデータは必要である。

[`naming.json`](naming.json) は各管理対象skillの種別と、サービス・業務ドメインskillの正規接頭辞を
定義する唯一の正本である。skillを追加・改名・種別変更するときは同時に更新し、
`scripts/check-skill-naming.py` と `make check-skills` で検証する。

特定のサービス・アプリや業務ドメインに紐づかない汎用skill（`consolidate-global-memory`、
`docx-proofreading` 等）は、この接頭辞ルールの対象外とし、動詞や主題から始める従来通りの命名でよい。

## Obsidian conversation records

Obsidianの会話Recordは、対象vaultの`docs/conversation-record-format.md`を形式の正本とする。保存・整備skillは通常とPrivateの会話を全文で保持し、Knowledge・Projectへの整理と区別する。skillの責務と原資料の扱いは[Obsidian skill workflow](../../docs/obsidian-workflow.md)を参照する。
