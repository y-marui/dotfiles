# Cloud sessions

Claude Code のクラウドセッション（claude.ai/code、モバイル、デスクトップの Cloud、Routines）で、
dotfiles と dotfiles-private が定義する AI 設定・skill・private data を使うための仕組み。
対象外: claude.ai のチャット（Cowork を含む）。そちらは `ai/skills/cloud.json` の同期（[Cloud Skills](../ai/skills/README.md#cloud-skills)）を使う。

## Constraints

公式ドキュメント（Claude Code on the web、Cloud environments、Settings）と実機のスパイク（2026-10-14）で確認した前提。

- クラウドセッションは `~/.claude/` 配下（CLAUDE.md、skills、settings.json、MCP）を引き継がない。
  リポジトリの `.claude/` と、claude.ai で有効化した Skills だけが読まれる。
- リポジトリの `enabledPlugins` / `extraKnownMarketplaces` は、クラウドセッションでは読み込まれない。plugin 経由の配布は使えない。
- 環境（Environment）の Setup script は、Claude Code の起動前に root で走る。結果はスナップショットされ、
  スクリプトか許可ホストを変えない限り約7日は再実行されない。
- 環境変数は Setup script の実行時点では見えない。セッション内のコマンドと SessionStart フックからは見える。
- VM 内の `~/.claude/CLAUDE.md`、`~/.claude/skills/`、`~/.claude/settings.json` の SessionStart フックは、Setup script が作ったものが読まれる。
- 添付していない public リポジトリは匿名で clone できる。添付していない private リポジトリは、環境変数の PAT で clone（読み取り）できる。
- 添付していない（セッションの sources に無い）リポジトリへの push は、Git プロキシが認証情報を付けず 403 になる。
  PAT を credential helper に渡しても通らない。`add_repo` で sources に追加すると、既存の clone のまま push できる
  （実機で確認。承認の求めはなかった）。

## Design

~~~text
Setup script（キャッシュされる）
  └─ public の dotfiles を clone → scripts/cloud-bootstrap.sh setup
       ├─ ~/.ai/*、~/.claude/CLAUDE.md、~/.claude/rules/、bin を link
       ├─ ai/skills/cloud-code.json の skill だけを ~/.claude/skills へ展開（ai/skills/apply.sh）
       └─ ~/.claude/settings.json の SessionStart に session を登録（既存のフックは残す）

SessionStart フック（起動時と復元時）
  └─ scripts/cloud-bootstrap.sh session
       ├─ dotfiles を git pull し、更新後のスクリプトで実行し直す
       ├─ DOTFILES_PRIVATE_TOKEN があれば dotfiles-private を clone/pull → ~/.identity を link
       ├─ VAULT_TOKEN があれば obsidian-vault を blob:none で clone/pull
       └─ CLAUDE_ENV_FILE へ PATH・DOTFILES_DIR・OBSIDIAN_VAULT_ROOT を追記
~~~

- Setup script は薄く保つ。ロジックは `scripts/cloud-bootstrap.sh` に置き、git で管理する。
- シェル・git・ssh・terminal の設定と `ai/claude/settings.json` は展開しない。
  `~/.gitconfig` のフックは identity が `anonymous` のとき commit を拒否するため、クラウドでは使えない。
- 展開する skill は `ai/skills/cloud-code.json` の明示リストだけ。ブラウザ操作・ローカルファイル・
  ローカル専用 MCP に依存する skill は載せない。`scripts/check-skills.sh` が、リストの名前が実在することを検証する。
- 外部 skill（`external.json`）は、Codex の skill-installer が無い環境では、固定した ref を `git` で取得する。
- 失敗してもセッションは止めない（終了コードは常に 0）。警告は SessionStart の出力とログ（`~/.cache/cloud-bootstrap.log`）に出る。

## Setup

専用の個人環境（例: `dotfiles-personal`）を作る。共有環境や Default には置かない。
環境変数と Setup script は、その環境を使う全員から読める。

1. ネットワークは Trusted にする。
2. 環境変数を設定する（値は GitHub の細粒度 PAT。値を docs やチャットに書かない）:
   - `DOTFILES_PRIVATE_TOKEN`: 対象は `dotfiles-private` のみ。Contents: Read-only。
   - `VAULT_TOKEN`（Project Home を使う場合）: 対象は `obsidian-vault` のみ。Contents: Read-only。
     起動時の clone/pull 専用で、書き込みには使えない（前述のプロキシの制約）。
3. vault のデフォルトブランチに、PR 必須の ruleset を設定し、クラウドから main へ直接 push できないようにする。
   vault への書き込みは、プロキシが付ける GitHub 接続の認証情報で行われ、ブランチ単位の制限は無い。
   この ruleset が書き込み範囲の境界になる。
4. Setup script に次を設定する:

~~~text
#!/bin/bash
export GIT_TERMINAL_PROMPT=0
BASE="$HOME/src/github.com/y-marui"
mkdir -p "$BASE"
[ -d "$BASE/dotfiles/.git" ] || git clone --depth 1 https://github.com/y-marui/dotfiles "$BASE/dotfiles" || true
bash "$BASE/dotfiles/scripts/cloud-bootstrap.sh" setup || true
exit 0
~~~

## Verify

新しいセッションを、この環境で起動し、次を確認する。

- セッション開始時に `[cloud-bootstrap] private=ok vault=ok` の1行が出る。
- `/context` の Memory files に `/root/.claude/CLAUDE.md` と `rules/cloud-environment.md` が出る。
- `grilling`、`session-handoff`、`session-finish` が skill 一覧にある。
- `ls ~/.identity` で private data の link を確認できる。

## Writing to the vault

1. 書き込む前に、`add_repo` で `y-marui/obsidian-vault` を `access: push` でセッションに追加する。
2. 起動時に clone 済みの `$OBSIDIAN_VAULT_ROOT` で、`ai/cloud/<日付>-<短い主題>` ブランチを作って push する。
   main へは push しない。プロキシはブランチの削除を拒否するため、不要になったブランチは GitHub 上で消す。
3. main への統合は、ローカルで `session-finish` を使う。
4. 無人実行（Routines）で書き込む場合も、同じ手順で `add_repo` を呼ぶ。

## Operations

- **skill の追加**: `ai/skills/cloud-code.json` に名前を足す。Setup script の変更は不要で、次のセッション開始時に反映される。
- **失敗時の調査**: `~/.cache/cloud-bootstrap.log` を見る。トークンの値はログに出ない。
- **トークンの更新**: PAT の期限切れでは、private/vault は取得されず警告だけが出る。環境変数を更新し、新しいセッションを始める。
- **rollback**: 環境の Setup script を空にして、環境変数を削除する。リポジトリ側の変更は、通常の revert で戻る。

## Known limits

- 復元時（`source=resume`）に SessionStart フックが再実行されるかは、実機で未確認。動かなくても、起動時の更新は行われる。
- commit の identity は、クラウド側が設定する（実機で `Claude` / `noreply@anthropic.com` を確認）。
- `ai/skills/apply.sh` の Windows 版（`apply.ps1`）には、外部 skill の git 取得経路と `SKILL_SELECT_FILE` を実装していない。クラウドは Linux 専用のため。
