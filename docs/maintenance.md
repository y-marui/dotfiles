# Maintenance

`docs/` ファイルの更新案をローカル LLM で作るためのプロンプト集。ローカル LLM は読み取り専用で使用し、主担当 AI が根拠と実ファイルを照合してから確認済みの更新案だけを保存する（[AI_COLLABORATION_RULES.md](dev-charter/AI_COLLABORATION_RULES.md) の Local LLM Delegation 参照）。

## Updating docs/architecture.md

```
dotfiles リポジトリの docs/architecture.md を更新してください。

手順:
1. リポジトリ直下のディレクトリ構造（bin/, shell/, git/, terminal/, karabiner/, ai/,
   macos/, windows/, scripts/, docs/ 等）を確認する
2. Makefile・bin/unix/dots・bin/unix/ghq-status 等の主要エントリーポイントを読む
3. 既存の docs/architecture.md を読む
4. 以下のフォーマットに沿った更新案を、根拠となるファイルパスとともに出力する

フォーマット:
# Architecture
## Overview
<!-- 3行以内 -->
## Entry Points
- `パス/ファイル` — 説明
## Directory Structure
| ディレクトリ | 役割 |
## Key Dependencies
| ライブラリ / モジュール | 用途 |

注意: Overview は3行以内、ファイルレベルの詳細は書かない（file-map.md に委譲）、主要な依存のみ列挙する。
```

## Updating docs/file-map.md

```
dotfiles リポジトリの docs/file-map.md を更新してください。

手順:
1. 直近の変更（git diff / 直近のコミット）で触れたファイルを確認する
2. 既存の docs/file-map.md を読む
3. 該当ファイルについて、以下のフォーマットで追記案を、根拠となるファイルパスとともに出力する

フォーマット:
## [モジュール / 機能名]
| ファイル | 役割 | 主な依存先 |
|---|---|---|
| `path/to/file` | 説明 | `path/to/dependency` |

注意: 全ファイルを網羅しなくてよい。未探索ファイルは記載しない。更新時は _最終更新: YYYY-MM-DD_ も更新する。
```

## Syncing dev-charter scripts

dev-charter は lite 版を `git subtree` で取り込んでおり、lite は `scripts/check-*.sh` を配布しない。
`scripts/` のスクリプトは full ブランチからの手動コピーで、`git subtree pull` では更新されない。
取得・更新の手順の正本は
[`docs/dev-charter/SECURITY_POLICY.md`](dev-charter/SECURITY_POLICY.md)（lite のまま一部のフックだけ使う場合）。

dev-charter を更新したとき（`chore: update dev-charter to ...`）は、次で full の最新と比較する。

~~~sh
git fetch dev-charter full
for f in scripts/check-*.sh; do
  git diff --no-index --stat <(git show "dev-charter/full:$f" 2>/dev/null) "$f"
done
~~~

差分があれば取り込む。意図的な独自差分は、スクリプト内のコメントに理由を残す。現在の独自差分:

- `check-ai-context-reference.sh`: `GEMINI.md` を検査しない（Gemini 設定管理の削除に合わせた除外）
- `check-markdown-heading-language.sh`: YAML frontmatter を読み飛ばす修正がローカルにだけある
  （`ai/skills/*/SKILL.md` 対応。dev-charter 側は y-marui/dev-charter#162）
