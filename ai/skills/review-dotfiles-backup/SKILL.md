---
name: review-dotfiles-backup
description: "Audit timestamped ~/.dotfiles-backup entries against the dotfiles repository and live system before deciding whether they are redundant. Use when the user asks to check, clean up, or prune dotfiles backups, or when `dots check` reports them; never infer safe deletion from file names alone."
---

# Review dotfiles backup

`scripts/install.sh` と対応するPowerShellスクリプトは、既存ファイルをリンクへ置換または管理場所へ移行する前に `~/.dotfiles-backup/YYYYMMDDHHMMSS/` へ退避する。ファイル名や最初の数件だけで判断せず、各エントリを現在のリポジトリとライブ状態に照合する。

## Step 1: Inventory

すべての `~/.dotfiles-backup/YYYYMMDDHHMMSS/` と内容、日付範囲を一覧する。開始時は `find ~/.dotfiles-backup -mindepth 2 | sort` でよい。

## Step 2: Classify each entry, then verify the classification

各エントリを分類して、実際に照合する。

- **古い状態スナップショット**: `Brewfile`、Dock設定、`~/.claude.json`、`~/.codex/config.toml` 等。バックアップと現在の追跡対象・ライブ対象をdiffし、バックアップだけの内容は詳しく調べる。
- **移行済みの残存物**: 退避元と同等物がリポジトリまたは有効なリンクにあることを確認する。
- **意図的に管理外とした残存物**: サードパーティskill等は、リポジトリ全体に管理対象がないことを確認してから管理外と判断する。
- **不要な成果物**: 再生成可能なキャッシュまたは消滅・置換済みパスへのリンクは、実際にそうであることを確認する。

## Step 3: Handle credentials carefully

AIツールその他のアプリの設定ファイル（`~/.claude.json`、`~/.codex/config.toml` など）には、無害な設定値に混じって、MCPサーバーや連携のライブOAuth bearer token、APIキー、その他のシークレットが含まれることが多い。**このようなファイルを `cat` するなど、完全な内容を出力へ出してはならない。** 代わりに対象を限定した比較を使う。

- バックアップとライブファイルを `diff` する、JSONならキーだけを比較する。
- `grep` は確認対象のフィールドだけに限定し、値より先にキー一覧を比較する。

ライブトークンや認証情報らしきものを誤って出力した場合は、そこで停止して直ちにユーザーへ伝え、ローテーションできるようにする。黙って作業を続けない。

## Step 4: Decide and act

- **固有で残す価値があるもの**: 通常の方法でリポジトリへ取り込むか、管理対象外の理由を説明する。内容を理解せず生のバックアップを戻さない。
- **すべて冗長または不要**: 分類と理由を要約し、ユーザー自身が実行する次のコマンドを渡す。

  ```bash
  rm -rf ~/.dotfiles-backup
  ```

  このコマンドは自分で実行しない。ユーザーが「削除して」と依頼していても同じである。

## Reporting back

分類ごとの概数と結論を報告する。残すものがあれば、編集したファイルと理由を具体的に示す。個々の `find` / `diff` コマンドは列挙しない。
