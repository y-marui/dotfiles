# 設計ドキュメント

AI がこのリポジトリを改修する際の「なぜこうなっているか」を記録する。

---

## 設計方針：シンボリックリンク方式

`~/.zshrc` 等をリポジトリへのシンボリックリンクにすることで、
ファイルを編集すれば即座にリポジトリに反映される仕組みを採用している。

**選択理由：**
- `stow` や `chezmoi` のような外部ツールに依存しない
- `make install` 1コマンドで完結する
- スクリプトが読めれば仕組みが完全に把握できる

既存ファイルは `~/.dotfiles-backup/YYYYMMDDHHMMSS/` に自動バックアップしてから置き換える。

---

## 3層管理の考え方

| 層 | 場所 | 内容 |
|----|------|------|
| 公開 | このリポジトリ | ツール設定、エイリアス、スクリプト |
| 非公開 | `dotfiles-private` | 個人用メールアドレス、SSH、非公開の AI 設定等 |
| ローカル | `~/.zshrc.local` / `host/<hostname>.zsh` | APIキー、マシン固有パス等のシークレット |

シークレットは絶対にこのリポジトリにコミットしない。
`make private` で GitHub の private repository から取得する運用とする。

---

## AI agent の skill / plugin / MCP 管理境界

ツール非依存の Agent Skills は `ai/skills/<skill-name>/` を正本とし、同じ実体を
Codex の公式個人配置 `~/.agents/skills/<skill-name>/` と Claude Code の個人配置
`~/.claude/skills/<skill-name>/` へディレクトリ単位でリンクする。ツール固有の機能や
記法に依存するものだけを `ai/{codex,claude}/skills/<skill-name>/` に置き、それぞれの
個人配置へリンクする。共通 skill とツール固有 skill の同名定義は禁止する。
`~/.agents/skills` 全体をリンクしないのは、Codex やプラグインが管理する skill と
自作 skill の所有範囲を分離するため。Claude Code 側も同様に skill root 全体を所有しない。
各 agent の実際の skill root を走査するため、アプリ・CLI・手動で追加された未管理 skill は
削除されず `+actual` として検知される。Codex は正規配置 `~/.agents/skills` に加え、
Codex 自身や skill-installer が利用する `~/.codex/skills` も探索し、`.system` 以外を
`+codex` として検知する。後者は検知専用で、`apply` / `prune` では変更しない。

`~/.codex/skills` に管理対象と同名の skill がある場合、インストール時に削除せず
`~/.dotfiles-backup/<timestamp>/codex-skills/` へ退避する。`.system` はCodex管理とする。
外部・curated skillは `ai/skills/external.json` にrepo/path/ref/targetを宣言し、公式
skill-installerで `~/.local/share/dotfiles/skills/` へ取得する。本体をrepoへvendorせず、
Claude CodeとCodexから同じキャッシュへリンクする。

`~/.codex/config.toml` は手動設定だけでなく、プロジェクトの trust、プラグイン、
デスクトップアプリ固有パスなども含む可変ファイルなので、全体をシンボリックリンク
しない。公開可能で安定した共通設定は公開 repo、個人情報やシークレットを含む設定は
`dotfiles-private/ai/codex/`、端末・セッション状態はローカル専用とする。

MCP と plugin は `ai/{claude,codex}/{mcp,plugin}/` に公開可能な宣言を置き、CLI で
統合済みの実態またはアプリと共有する実体ファイルを検査する。`apply` は不足・設定不一致を
追加または更新し、削除は明示的な `prune` だけが行う。MCP は local（stdio）/ remote
（HTTP）の両方を検知する。Claude Code は user scope に加え、既知 project の local scopeと
`.mcp.json` も検査するが、local scopeは端末・リポジトリ固有、project scopeは
リポジトリ共有設定として区別し、どちらも削除しない。loopback IDE MCP、
plugin内包MCP、ChatGPT/Codexアプリ内部MCPも所有元を表示し、直接MCPの差分・削除対象から外す。

`prune` の削除境界は、MCPが未宣言のuser/global直接登録、pluginが未宣言のインストール、
skillがdotfilesまたは専用キャッシュを指す未宣言リンクに限定する。MCP設定は削除前に
`~/.dotfiles-backup/` へ退避し、Claude pluginの永続データは保持する。
静的認証ヘッダーを含む `~/.claude.json` と `~/.codex/config.toml` は `600` を維持する。

外部 AI CLI を MCP として接続する場合は、提供元が公式に公開する server mode または
remote server のみ採用する。現在の Codex 管理対象は GitHub Remote MCP と
その Copilot toolset、および `claude mcp serve` だけで、Copilot CLI / Gemini CLI /
Ollama 用の独自 bridge は作らない。

---

## シェルファイルの責務分離ルール

zsh の起動フローに合わせて責務を分離することで、設定の重複・競合を防ぐ。

```
zshenv → zprofile → zshrc → zlogin
```

| ファイル | 責務 | 理由 |
|---------|------|------|
| `shell/profile` | sh 互換の共通環境変数・PATH | bash でも同じ設定を使うため |
| `shell/zshenv` | 全 zsh セッション共通の最小設定 | 非インタラクティブでも必要なもの |
| `shell/zprofile` | zsh ログイン時の Homebrew PATH 等 | macOS 固有の初期化 |
| `shell/zshrc` | エイリアス・関数・補完・ツール初期化 | インタラクティブ専用 |
| `shell/zlogin` | ログイン後処理（zcompdump コンパイル等） | zprezto デフォルト踏襲 |

**`shell/profile` に zsh 固有構文（`[[` 等）を書かない**のは、
bash から `source ~/.profile` した際に構文エラーになるため。

---

## zprezto との共存方針

`~/.zprezto` 本体はこのリポジトリで管理しない。理由：

- zprezto はサブモジュール込みで大きく、dotfiles に含めると管理が複雑になる
- Prezto と配下の Powerlevel10k を upstream の履歴に沿って更新する

管理対象は `shell/zpreztorc`（モジュール選択・テーマ設定）のみ。
Prezto 本体は外部 Git リポジトリのまま、`scripts/setup-prezto.sh` で初回 clone、
`scripts/update-prezto.sh` で fast-forward 更新とサブモジュール同期を行う。
Powerlevel10k は Prezto が固定するサブモジュールを使い、単独 clone や Homebrew 版と
二重管理しない。

---

## ホスト差分管理の仕組み

複数台の Mac でホスト名が異なることを利用する：

```
host/
  <hostname>.zsh        # zsh のマシン固有設定
  <hostname>.gitconfig  # gitconfig のマシン固有設定
  .gitignore            # 中身: *（全ファイルを git 管理外に）
```

`shell/zshrc` の末尾で `host/$(hostname -s).zsh` を source する。
`host/` 配下は `.gitignore` で全て除外されるため、シークレットを書いても安全。

`make init` でホスト名に応じたテンプレートを自動生成する。

---

## git/gitconfig の includeIf 設計

組織ごとに異なるメールアドレス・署名キーを使い分けるため、
`gitdir:` 条件でリポジトリのパスに応じて設定ファイルを切り替える。

```
~/src/github.com/<public-org>/  → ~/.gitconfig.d/public  （個人公開）
~/src/github.com/<private-org>/ → ~/.gitconfig.d/private （個人非公開）
~/src/git.overleaf.com/         → ~/.gitconfig.d/overleaf （Overleaf）
```

`[includeIf]` の設定自体（組織名・ディレクトリ構造）は `~/.gitconfig.d/includes` に記載し、
Private Gist で管理する（`setup-private.sh` がシンボリックリンクを作成）。
各 `~/.gitconfig.d/*` の中身（[user] name/email/signingkey 等）も同様。
