# Claude Code skills

個人 skill は `ai/claude/skills/<skill-name>/SKILL.md` として追加する。
`dots claude apply --skill-only` で `~/.claude/skills/<skill-name>` へ個別にリンクされる。

ディレクトリ全体は所有しないため、Claude Code アプリや CLI が追加した skill は保持され、
`dots claude diff --skill-only` で未管理の `+actual` として検知される。
