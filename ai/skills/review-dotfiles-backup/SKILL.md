---
name: review-dotfiles-backup
description: "Audit the timestamped subdirectories under ~/.dotfiles-backup (the directory dotfiles' scripts/install.sh moves a file into whenever `make install` / `dots update` can't symlink over it) and decide, per entry, whether it holds information not already reflected in the dotfiles repo or the current live system state. If everything is redundant, hand the user the exact `rm -rf` command instead of running it. Use this whenever the user mentions ~/.dotfiles-backup, asks to check/clean up/prune dotfiles backups, or when `dots check` reports backup files accumulating there — don't just glance at file names and guess; actually compare content against the repo and live state before concluding anything is safe to discard."
---

# Review dotfiles backup

`scripts/install.sh`（および対応するPowerShellスクリプト）は、実ファイルをシンボリックリンクに置き換える前に退避する場合、またはdotfiles管理下の新しい場所へ移行する場合に、`~/.dotfiles-backup/YYYYMMDDHHMMSS/` を作成する。これらは通常削除されないため、数か月分が蓄積する。単にファイル一覧を報告するのではなく、実際の内容を確認してエントリごとに判断する。

## Why content review matters here

ファイルの*名前*だけでは、安全に破棄できるかはほとんど分からない。`config.json` は代えの利かないユーザー設定かもしれないし、次回起動時に再生成されるアプリのテレメトリかもしれない。確認する唯一の方法は、現在のdotfilesリポジトリとライブのシステム状態を比較することである。似たようなディレクトリが大量にある場合（たとえばほぼ同一の `Brewfile` スナップショットが数十件）でも、この手順を省略しない。最初の1、2件から推測せず、パターンを確認する。

## Step 1: Inventory

すべての `~/.dotfiles-backup/YYYYMMDDHHMMSS/` ディレクトリと内容を一覧する（開始時には `find ~/.dotfiles-backup -mindepth 2 | sort` で十分）。日付範囲も確認する。数か月に及ぶ場合は一度も整理されていない可能性が高く、古いものほど不要になっている可能性が高い。

## Step 2: Classify each entry, then verify the classification

ほとんどのエントリはいずれかの分類に当てはまる。エントリの分類を明示し、次へ進む前に実際に確認する。重要なのは推測ではなく確認である。

- **継続的に変化する状態の古いスナップショット。** Homebrewの `Brewfile` ダンプ、macOS Dock設定（`dock-apps.txt`、`dock-sidebar.txt`、`dockfile.cache`）、アプリの状態・テレメトリファイル（`~/.claude.json`、`~/.codex/config.toml`）など。これらは設計上ほぼ毎回変化し、現在のライブファイルまたはdotfilesリポジトリで追跡される版が正本である。バックアップは定義上古く、置き換え済みである。推測せず、バックアップと現在の追跡対象・ライブ対象をdiffして確認する。バックアップにしかない内容があれば古いスナップショットではないため、詳しく調査する。
- **移行済みの残存物。** 構成変更中に退避されたファイルやディレクトリ（例: `ai/skills/` へ移したagent skill）。同等物がdotfilesリポジトリ、またはそこからの有効なシンボリックリンクとして正しく存在するか確認する。存在すれば、バックアップは成功した移行による冗長な残存物である。
- **意図的に管理外とした移行残存物。** 退避されたものが、そもそもdotfiles管理対象ではない場合がある。たとえば、このリポジトリの `ai/skills/` に属さないサードパーティまたはマーケットプレイス由来のskillである。消失ではなく適切な管理外と判断する前に、想定した場所だけでなくリポジトリ全体に本当に存在しないことを確認する。
- **実際に不要になった成果物。** 再生成可能なキャッシュ（シェル補完ダンプなど）、またはすでに存在しないdotfilesパス（改名・再構成済み）を指すシンボリックリンク。対象が本当に消滅または置換済みだと確認できれば、安全に破棄できる。

## Step 3: Handle credentials carefully

AIツールその他のアプリの設定ファイル（`~/.claude.json`、`~/.codex/config.toml` など）には、無害な設定値に混じって、MCPサーバーや連携のライブOAuth bearer token、APIキー、その他のシークレットが含まれることが多い。**このようなファイルを `cat` するなど、完全な内容を出力へ出してはならない。** 代わりに対象を限定した比較を使う。

- バックアップと現在のライブファイルを `diff` する、またはJSONを解析してキーだけを比較する（例: 構造全体を出力せず `mcpServers` のような特定キーを確認する `python3 -c "import json; ..."`）
- 確認対象のフィールドだけを `grep` する
- 値を比較する前にキー一覧（`.keys()`）を比較する

ライブトークンや認証情報らしきものを誤って出力した場合は、そこで停止して直ちにユーザーへ伝え、ローテーションできるようにする。黙って作業を続けない。

## Step 4: Decide and act

- **本当に固有で残す価値があるものが見つかった場合**: 通常の方法でdotfilesリポジトリへ取り込む。該当する追跡ファイルを編集するか、ホスト固有などの理由で対象外と判明したなら、その理由を明確に説明する。意味を理解しないまま、生のバックアップファイルを元の場所へコピーしない。
- **すべてが冗長または不要と確認できた場合**: 確認した内容と、各分類を安全に破棄できる理由を要約する。そのうえで、ユーザー自身が実行する正確なコマンドを渡す。

  ```bash
  rm -rf ~/.dotfiles-backup
  ```

  このコマンドを自分で実行しない。データの恒久的な削除は、分析にどれほど確信があっても、またユーザーが「削除して」と言っていても、ユーザー自身が行う。ルールを明示してコマンドを渡す。

## Reporting back

分類ごとに、おおよそ何件が該当し何を結論づけたかをユーザーに伝える。すべての `find` / `diff` コマンドを逐一報告する必要はない。残す価値のあるものが見つかった場合は、どのファイルをなぜ編集したかを具体的に伝える。
