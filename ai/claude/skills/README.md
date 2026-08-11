# Claude Code skills

Claude Code 固有の機能や記法に依存する個人 skill だけを
`ai/claude/skills/<skill-name>/SKILL.md` として追加する。

ツール非依存の Agent Skills は `ai/skills/` に置く。
どちらも `dots claude apply --skill-only` で `~/.claude/skills/<skill-name>` へ個別にリンクされる。

ディレクトリ全体は所有しないため、Claude Code アプリや CLI が追加した skill は保持され、
`dots claude diff --skill-only` で未管理の `+actual` として検知される。
外部skillの取得元は `ai/skills/external.json` で共通管理する。
