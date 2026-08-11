# Shared agent skills

Claude Code と Codex の両方で使える skill は `ai/skills/<skill-name>/SKILL.md` として追加する。

`dots claude apply --skill-only` は `~/.claude/skills/<skill-name>`、
`dots codex apply --skill-only` は `~/.agents/skills/<skill-name>` へ、同じ実体を個別にリンクする。

ツール固有の機能や記法に依存する skill だけを `ai/claude/skills/` または
`ai/codex/skills/` に置く。共通 skill とツール固有 skill で同じ名前は使用しない。

外部・curated skillは `external.json` に `name`、`repo`、`path`、固定した `ref`、
`targets` を宣言する。`apply --skill-only` は公式skill-installerでdotfiles専用キャッシュへ
取得し、両agentから同じ実体を参照する。宣言を削除した後に両agentで
`prune --skill-only` を実行すると、管理リンクと参照されなくなったキャッシュを退避する。
