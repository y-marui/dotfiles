# Shared agent skills

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

## Naming

特定のサービス・アプリと連携する skill は `<service>-<verb>-<object>` の順にし、
サービス名を先頭に置く（例: `spotify-distribute-liked-songs`、`glance-task-add-museum-event`）。
関連するskill同士が名前順で並ぶようにするため。コロン区切り（`service:verb`）は
plugin skillの表記（`plugin:skill`）と紛らわしいため使わない。

特定のサービス・アプリに紐づかない汎用skill（`consolidate-global-memory`、
`word-proofreading` 等）は、この接頭辞ルールの対象外とし、動詞や主題から始める
従来通りの命名でよい。
