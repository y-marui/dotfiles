# Dev Charter (lite)

> **このファイルは正本（日本語版）です。**
> 英語版（参照）は [README.md](README.md) を参照してください。

[dev-charter](https://github.com/y-marui/dev-charter) の **lite** 版。
プロジェクト種別を問わず普遍的に価値がある部分（AI コンテキストの整備、
GitHub Issues/Projects でのタスク管理、シークレット管理等）だけを収録して
いる。Python 開発環境・UI デザイン・収益化方針などソフトウェアプロジェクト
固有の内容は含まれない。収録内容は [CHARTER_INDEX.md](CHARTER_INDEX.md) を
参照。それらが必要な場合は `full` ブランチを検討すること。

## Install (git subtree)

```
git remote add dev-charter https://github.com/y-marui/dev-charter
git fetch dev-charter
git subtree add --prefix=docs/dev-charter dev-charter lite --squash
```

インストール後、以下のプロンプトを AI ツールに貼り付けてください：

```
docs/dev-charter/CHARTER_INDEX.md を読み、このプロジェクトに合わせて AI_CONTEXT.md 等を構成して
```

Quick Install のワンライナーでも同じことができる：

```bash
CHARTER_BRANCH=lite bash <(curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh)
```

## Update

Quick Install のワンライナーを再実行するだけでも更新できる。既存の導入と
そのブランチ（ここでは lite）を検知して `git subtree pull` を自動実行する
（未コミットの変更があれば自動で stash/復元し、テンプレートリポジトリの
場合は完全な再同期にフォールバックする）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh)
```

手動で更新する場合：`dev-charter` リモートが未設定の場合（プロジェクトを clone した直後など）は先に追加する：

```
git remote add dev-charter https://github.com/y-marui/dev-charter
git subtree pull --prefix=docs/dev-charter dev-charter lite --squash
```

> **Note（テンプレートリポジトリから作成したプロジェクト）:**
> GitHub テンプレートはファイルのみコピーし git 履歴を引き継がないため、`git subtree pull` は失敗します。
> `check-charter.yml` ワークフローがこのケースを自動検出して対処します。
> 手動で更新する場合は `git subtree pull` の代わりに以下を実行してください：
> ```bash
> git remote add dev-charter https://github.com/y-marui/dev-charter || true
> git fetch dev-charter
> SPLIT=$(git rev-parse dev-charter/lite)
> rm -rf docs/dev-charter/
> mkdir -p docs/dev-charter/
> git archive dev-charter/lite | tar -x -C docs/dev-charter/
> git add docs/dev-charter/
> git commit -m "Squashed 'docs/dev-charter/' content from commit ${SPLIT}
>
> git-subtree-dir: docs/dev-charter
> git-subtree-split: ${SPLIT}"
> ```

更新後は `git diff HEAD~1 HEAD --name-only -- docs/dev-charter/` で変更ファイル
を確認し、AI ツールにプロジェクトへの反映を依頼すること（lite には独立した
`UPDATE_CHECKLIST.md` が無い）。

## Version Check (CI)

`.github/workflows/dev-charter-check.yml` をプロジェクトに追加すると、
PR作成や main への push をきっかけに最新バージョンを確認し、古い場合は
update PR を作成します（直近7日以内に成功したチェックがあればスキップする
ため、活発な repo でも毎回チェックが走ることはありません）。**lite を
追跡するには `branch: lite` を明示的に指定する必要があります**：

```yaml
name: Dev Charter

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  check:
    name: Check
    if: github.actor != 'dependabot[bot]' && (github.event_name != 'pull_request' || github.event.pull_request.draft == false)
    uses: y-marui/dev-charter/.github/workflows/check-charter.yml@main
    with:
      branch: lite
    permissions:
      contents: write
      pull-requests: write
      actions: read

  gate:
    name: Dev Charter
    needs: [check]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Verify dev-charter check did not fail
        run: |
          result="${{ needs.check.result }}"
          if [ "$result" = "failure" ] || [ "$result" = "cancelled" ]; then
            echo "::error::dev-charter check did not succeed (got: $result)"
            exit 1
          fi
          echo "check result: $result (skipped is fine — draft or dependabot)"
```

> **Note:** `with: branch: lite` を書き忘れると、既定値の `full` を追跡してしまい、
> full の VERSION と lite の VERSION の違いにより、実際には最新でも
> 「outdated」と誤判定され続けます（あるいはその逆）。`check-charter.yml`
> 自身も、導入済みの `docs/dev-charter/CHARTER_INDEX.md` の variant と
> `branch` 入力が食い違っていれば検出してエラーにします。

> **Note:** dependabot が作成した PR や draft PR では `check` 自体がスキップされます
> （後述）。`gate` はその場合も `skipped` を正常として扱い、必ず `Dev Charter`（ワークフロー
> 自身の `name:` と同じ値）を報告します。Branch Protection（Ruleset）に必須ステータス
> チェックとして登録するのは `Check / check` ではなく `Dev Charter` です（[CI_POLICY.md
> の Ruleset 節](topics/CI_POLICY.md#branch-protection-ruleset)参照）。
> `check` job だけを直接必須チェックに登録すると、skip 時に `Check / check` という
> コンテキスト自体が一切報告されず、PR が `Expected — Waiting for status to be reported`
> のまま永久にブロックされます。

> **Note:** dependabot が作成した PR ではスキップされます（依存関係更新だけが動いている間はチェック不要という判断）。
> repo が完全に静止している間はチェックが走らないため、活動に関わらず定期的に確認したい場合は
> 上記に加えて低頻度の `schedule`（例：月1回）を併用してください。

> **Note:** Draft PR ではスキップされます（draft はそもそもマージできないため、チェックが
> 未報告のままでもリスクがない）。`on.pull_request.types` の `ready_for_review` により、
> draft を解除した際は改めて実行されます。

> **Note:** Branch Protection で direct push が禁止されている場合は、
> GitHub Actions bot の bypass rule を追加してください
> （Settings > Rules > Rulesets > Bypass list > GitHub Actions）。

## Makefile Helper

`git subtree pull` は作業ツリーに未コミットの変更があると失敗するため、
実行前に自動で `git stash` し、完了後に `git stash pop` で戻す。

導入時に `full` と `lite`（将来追加されるブランチも含む）のどちらを選んだかを
このターゲットが覚えている必要はない。既存の `docs/dev-charter/CHARTER_INDEX.md`
の `# Charter Index (<branch>)` マーカー（`scripts/publish-branch.sh` が生成。
マーカーが無ければ `full` 扱い）から毎回導入済みブランチを自動判定するため、
取り違えて更新してしまう事故（full 導入なのに lite で上書き、またはその逆）
を防げる。

```
.PHONY: update-charter
update-charter:
	CHARTER_UPDATE_ONLY=1 bash <(curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh)
```

`CHARTER_UPDATE_ONLY=1` により、万一まだ何も導入していない状態でこの
ターゲットを実行してしまっても、`full` を勝手に新規インストールせず、
full/lite どちらを入れるか確認（非対話環境ではエラーで案内）する。

## Badge for Adopting Projects

プロジェクトの README にこのバッジを追加すると、dev-charter の更新状態を可視化できます。

```markdown
[![Charter Check](https://github.com/{owner}/{repo}/actions/workflows/dev-charter-check.yml/badge.svg)](https://github.com/{owner}/{repo}/actions/workflows/dev-charter-check.yml)
```

`{owner}` と `{repo}` を自分のリポジトリのオーナー名・リポジトリ名に置き換えてください。

| 状態 | Status Badge |
|---|---|
| 未導入 / CI 未設定 | 赤（VERSION not found） |
| 導入済み・最新 | 緑 |
| 導入済み・更新必要 | 赤 |

---

*この文書には英語版 [README.md](README.md) があります。編集時は同一コミットで更新してください。*
