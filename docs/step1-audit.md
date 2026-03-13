# dotfiles Step 1 — 既存設定の読み取り結果

作成日: 2026-03-13

---

## 1. ファイルサマリー

| ファイル | 存在 | 主な内容 |
|---|---|---|
| `~/.zshrc` | ✅ | PATHの大量設定、pyenv/rbenv/nodebrew初期化、エイリアス、カスタム関数(g/cd/code/claude/pip)、gh/p10k補完、**APIキー2件含む** |
| `~/.zshenv` | ✅ | 非ログイン・非インタラクティブ時に `.zprofile` をsource するのみ（zpreztoデフォルト） |
| `~/.zprofile` | ✅ | BROWSER/EDITOR/PAGER設定、LANG、PATH(/usr/local)、LESS設定、末尾で `source ~/.zshrc`（二重ロードに注意） |
| `~/.zlogin` | ✅ | zcompdumpのコンパイル、loginシェルでfortune表示 |
| `~/.zlogout` | ✅ | ランダムお別れメッセージ表示のみ |
| `~/.zpreztorc` | ✅ | Preztoモジュール選択（environment〜prompt）、テーマ=powerlevel10k |
| `~/.bashrc` | ✅ | エイリアス群（py, ipy, jn, ls, tree, blender, ffmpeg等）、絶対パスのalias1件 |
| `~/.bash_profile` | ❌ | 存在しない |
| `~/.profile` | ✅ | `.bashrc` をsource、bash-completion、TeXbin PATH |
| `~/.vimrc` | ✅ | vim-bootstrap生成、プラグイン多数(NERDTree/airline/fzf/jedi等)、多言語対応(py/ruby/js等)、keymappings |
| `~/.tmux.conf` | ✅ | vi風キーバインド、pbcopy統合、ステータスバー設定、完成度高い |
| `~/.p10k.zsh` | ✅ | Powerlevel10k設定（大容量のためサマリー省略） |
| `~/.gitconfig` | ✅ | user設定、gitdir別includeIf（public/private/overleaf/others）、git-lfs、ghq設定、エイリアス |
| `~/.gitignore_global` | ✅ | VSCode/VisualStudio/macOS向けグローバルignoreパターン |

---

## 2. 取り込み候補の設定

### エイリアス

- `py="python"`, `ipy="ipython"` — zshrc/bashrc共通
- `ls="/bin/ls -G"` — zshrc/bashrc共通
- `sshy="ssh -Y"` — zshrc
- `pbg='ghq list -p | ... | pbcopy'` — zshrc
- `brew="env PATH=... brew"` — pyenv競合回避
- `tree="tree -C"`, `jn="jupyter notebook"` 等 — bashrc

### 環境変数・PATH

- `EDITOR=vim`, `VISUAL=vim`, `PAGER=less`, `LANG=ja_JP.UTF-8`
- `PYENV_ROOT`, `PYENV_VIRTUALENV_DISABLE_PROMPT=1`
- `PYTHONPYCACHEPREFIX=$HOME/.config/pycache`
- `LESS="-R"`, `LESSOPEN`（src-hilite-lesspipe）
- `XML_CATALOG_FILES`, `DICTIONARY=en_US`
- pyenv/rbenv/nodebrew/plenv の PATH追加と初期化
- Homebrew関連PATH（`/opt/homebrew/bin`, `/opt/homebrew/sbin`）
- `GOOGLEDRIVE_ROOT`, `DROPBOX_ROOT`, `ICLOUD_ROOT`, `ZOTERO_ROOT`（`$HOME` 相対なのでポータブル）

### カスタム関数

- `g()` — ghq+fzfでリポジトリ移動（zsh補完付き）
- `cd()` — cd後自動でls実行
- `code()` — ディレクトリによりcode/code-insidersを切り替え
- `claude()` — 終了時に未コミット変更を確認
- `pip()` — `pip search` をpip_searchにリダイレクト

### ツール設定（初期化）

- `eval "$(pyenv init -)"`
- `if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi`
- `if which plenv > /dev/null; then eval "$(plenv init -)"; fi`
- `export PATH=$HOME/.nodebrew/current/bin:$PATH`

### その他

- `setopt IGNOREEOF`（Ctrl+D誤ログアウト防止）
- `setopt COMPLETE_IN_WORD`
- p10k instant promptブロック
- zprezto初期化
- gitconfig: `merge.ff=false`, `pull.ff=only`, `alias.cleanup`, `alias.root`
- `.gitignore_global` の内容全体

---

## 3. マシン固有設定（ローカルのみ管理候補）

- `ghq.root = /Users/yuki/src`（`~/.gitconfig`）
- `core.excludesfile = /Users/yuki/.gitignore_global`（`~/.gitconfig`）
- `commit.template = /Users/yuki/.stCommitMsg`（`~/.gitconfig`）
- `alias uninstall-spyder=/Users/yuki/Library/spyder-6/uninstall-spyder.sh`（zshrc/bashrc）
- `export PATH="$HOME/src/github.com/astj/ghq-migrator:$PATH"`（特定リポジトリのパス）
- `[includeIf "gitdir:~/src/github.com/y-xxxxxxxxxx/"]` → `~/.gitconfig-private`（組織固有）
- `[includeIf "gitdir:~/src/git.overleaf.com/"]` → `~/.gitconfig-overleaf`（サービス固有）
- `[includeIf "gitdir:/Volumes/*/Users/yuki/..."]`（外付けディスクの絶対パス）
- `fpath+=$(brew --prefix)/share/zsh/site-functions`（brewプレフィックスに依存）

---

## 4. シークレット候補（コミット禁止候補）

| 変数/場所 | 値（先頭のみ） | ファイル |
|---|---|---|
| `YAHOO_APP_ID` | `dj00aiZp...` | `~/.zshrc` L4 |
| `HOMEBREW_GITHUB_API_TOKEN` | `ghp_xBy7...` | `~/.zshrc` L160 |
| コメントアウト済みGitHub Token（y-marui用） | `ghp_GmeD...` | `~/.zshrc` L168 |
| コメントアウト済みGitHub Token（y-muen用） | `ghp_GmPP...` | `~/.zshrc` L169 |
| `~/.gitconfig-private` の内容 | 未読（組織固有のuser設定等が想定される） | `~/.gitconfig-private` |

> **注意**: コメントアウトされたトークンも git 履歴に残るため、コミット前に削除が必要です。
> `HOMEBREW_GITHUB_API_TOKEN` はすでに有効なトークンが平文で存在しています。

---

## 確認事項（Step 2 移行前）

1. シークレット候補としてリストアップした設定に漏れ・誤りはないか
2. マシン固有設定として除外する設定に漏れ・誤りはないか
3. 取り込み候補から除外したいものはあるか（例: Linux向けエイリアス `wmctrl`, `revive`, `apm-upgrade` など）
