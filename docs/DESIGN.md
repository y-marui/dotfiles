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

## Codex 設定の管理境界

Codex の自作 skill は `ai/codex/skills/<skill-name>/` を正本とし、公式の個人 skill
配置である `~/.agents/skills/<skill-name>/` へディレクトリ単位でリンクする。
`~/.agents/skills` 全体をリンクしないのは、Codex やプラグインが管理する skill と
自作 skill の所有範囲を分離するため。

旧配置 `~/.codex/skills` の同名 skill は、インストール時に削除せず
`~/.dotfiles-backup/<timestamp>/codex-skills/` へ退避する。`.system` と公式 curated
skills は Codex 側の更新に追従するため vendor しない。

`~/.codex/config.toml` は手動設定だけでなく、プロジェクトの trust、プラグイン、
デスクトップアプリ固有パスなども含む可変ファイルなので、全体をシンボリックリンク
しない。公開可能で安定した共通設定は公開 repo、個人情報やシークレットを含む設定は
`dotfiles-private/ai/codex/`、端末・セッション状態はローカル専用とする。

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
