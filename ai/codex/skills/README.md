# Codex-specific skills

Codex 固有の機能や記法に依存する個人 skill だけを
`ai/codex/skills/<skill-name>/SKILL.md` として追加する。

ツール非依存の Agent Skills は `ai/skills/` に置く。
どちらも `dots codex apply --skill-only` で `~/.agents/skills/<skill-name>` へ個別にリンクされる。

`dots codex diff --skill-only` は正規配置 `~/.agents/skills` に加え、Codex または
skill-installer が使用する `~/.codex/skills` も探索する。後者は `.system` を除いて検知のみ行い、
`apply` / `prune` では変更しない。外部skillを管理対象にする場合は `ai/skills/external.json`
へ宣言し、共通キャッシュから `~/.agents/skills` へリンクする。

Codexが `~/.codex/skills` へ直接作成したskillを管理対象にする場合は、`ai/skills/`
（ツール非依存）または `ai/codex/skills/`（Codex固有）へ実体を移し、frontmatterの `name`
をディレクトリ名に合わせてから `apply --skill-only` でリンクし直し、`~/.codex/skills` 側の
生ディレクトリは削除する。命名規則は [ai/skills/README.md](../skills/README.md#naming) を参照。
