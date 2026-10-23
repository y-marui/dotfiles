---
description: dotfiles-private の管理、マシン固有設定、profile の層、Brewfile.local、環境変数
---

# Private and Local-Only Settings

Git の user 情報・SSH config・Dock・アプリケーションショートカット設定は `dotfiles-private`（GitHub プライベートリポジトリ）で管理する。
private側は設定データと `links.conf` の対応表だけを保持し、リンク操作はこのリポジトリの
`install` / `links` / `check` / `uninstall` が行う。

新しい private repository は `make private-scaffold` で `.example` 付きの安全な雛形を
生成できる。既存パスは上書きせず、設定完了までリンクを有効化しない。ファイル一覧、
有効化手順、public側pre-commitによる条件付き検証は
[dotfiles-private Repository](private-repository.md) を参照。

```bash
# リポジトリを設定
cp scripts/.env.example scripts/.env
vi scripts/.env  # PRIVATE_REPO を記入（例: y-marui/dotfiles-private）

# クローン
make private
```

## Local-Only Settings

マシン固有の設定は以下のファイルに書く（git 管理外）：

- `./host/$(hostname -s).zsh` — zsh のマシン固有設定
- `./host/role` — 端末の役割（`work` か `other` の1語）。`work` の端末だけ `dots ghq get` と pipx の `ghq:` 指定の editable 導入を行う（[specification.md](specification.md#dots-ghq-get)）
- `~/.profile.local` — zsh / bash 共通。このMacだけの設定や、privateにも置かない機密値（`shell/profile.local.example` をコピー）
- `~/.zshrc.local` — zsh専用の追加設定（`shell/zshrc.local.example` をコピー）
- `~/.bashrc.local` — bash: 自動的に読み込まれる追加設定
- `macos/Brewfile.local` — Homebrew: このマシン固有のパッケージ（`make init` で空ファイルを生成）

## Profile Settings Layers

`~/.profile` は、後の層で前の層を上書きできる順に設定を読む。

1. `shell/profile` — OS共通の公開設定
2. macOSのみ `macos/profile`（`~/.profile.macos` へリンク）
3. dotfiles-private の `shell/profile.private`（`~/.profile.private` へリンク）
4. 未管理の `~/.profile.local`

複数の自分のマシンで共有する個人用パスは dotfiles-private へ、このMacだけの値とトークン等の認証情報は `~/.profile.local` へ置く。zshだけに関わる設定は `~/.zshrc.local`、bashだけに関わる設定は `~/.bashrc.local` を使う。

## Brewfile.local — Machine-Specific Homebrew Packages

メインの `Brewfile` に含めたくない（他のマシンには入れたくない）パッケージを管理する。

```bash
# make init で凡例付き空ファイルが生成される
make init

# Brewfile.local を編集してパッケージを追加する
vi macos/Brewfile.local
```

記法は `Brewfile` と同じ:

```ruby
brew "some-work-tool"        # CLI ツール
cask "proprietary-app"       # GUI アプリ（Cask）
tap "org/tap"                # Tap
mas "App Name", id: 1234567  # Mac App Store
vscode "publisher.extension" # VS Code 拡張
```

**自動整合（`dots brew sync` 実行時）:**

| 状況 | 動作 |
|------|------|
| パッケージをシステムからアンインストールした | `Brewfile.local` からも自動除去 |
| パッケージをメインの `Brewfile` に追記した | `Brewfile.local` からも自動除去（重複防止） |

**インストール（`dots brew apply` 実行時）:**
`Brewfile.cache`との差分から、`Brewfile` / `Brewfile.local`にのみ存在するエントリを
一時Brewfileへ抽出して適用する。管理ファイルにないエントリがある場合だけcleanupするため、
差分と無関係な既存パッケージは処理しない。

`dots brew apply --full`は従来のapplyと同じく、`Brewfile`と`Brewfile.local`を
それぞれ`brew bundle install`へ渡して全件適用した後、cleanupを実行する。

## Environment Variables That Need Configuring

以下の変数は `~/.profile.local` に設定する。

| 変数 | タイミング | 説明 |
|------|-----------|------|
| `DOTFILES_DIR` | ghq 等で `~/dotfiles` 以外にクローンした場合は**必須** | dotfiles のクローン先パス（例: `/path/to/dotfiles`）。未設定時は `~/dotfiles` が使われる |
| `HOMEBREW_GITHUB_API_TOKEN` | `brew search` 等でレート制限に当たる場合 | GitHub API への認証トークン。現在の Homebrew では必須ではないが、API 制限が頻繁に発生する場合に設定する |
