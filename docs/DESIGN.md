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
| 半公開 | Private Gist | `gitconfig-private`（個人用メールアドレス等） |
| ローカル | `~/.zshrc.local` / `host/<hostname>.zsh` | APIキー、マシン固有パス等のシークレット |

シークレットは絶対にこのリポジトリにコミットしない。
`make private` で Private Gist から取得する運用とする。

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
- `git clone --recursive` を強制したくない

管理対象は `shell/zpreztorc`（モジュール選択・テーマ設定）のみ。
zprezto 本体は新規マシンで別途 `git clone` する。

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
~/src/github.com/y-marui/   → ~/.gitconfig-public  （個人公開）
~/src/github.com/y-xxxxxxxxxx/ → ~/.gitconfig-private （個人非公開）
~/src/git.overleaf.com/     → ~/.gitconfig-overleaf （Overleaf）
~/src/github.com/           → ~/.gitconfig-others  （その他）
```

これらの `~/.gitconfig-*` はこのリポジトリに含めず、
Private Gist または `~/.gitconfig.local` で管理する。
