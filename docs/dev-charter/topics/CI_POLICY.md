# CI Policy (lite)

full と共通の内容（job 設計・concurrency・cost optimization 等）を含む。branch
protection のみ lite 専用の設定に差し替えている。full 側の詳細は
[CI_POLICY.md（full）](https://github.com/y-marui/dev-charter/blob/full/topics/CI_POLICY.md)
を参照。

## Naming Convention

| 対象 | 規則 | 例 |
|---|---|---|
| ワークフローファイル名 | 機能を表す小文字 + ハイフン | `ci.yml`, `charter-check.yml` |
| ワークフロー `name` | タイトルケース、短く端的に | `CI`, `Dev Charter` |
| job ID | 小文字スネークケース | `lint`, `test`, `build` |
| job `name` | タイトルケース。追加説明が必要な場合は括弧付きで補足 | `Lint`, `Test`, `Test (pytest)`, `Build`, `Security scan (pre-commit)` |

### Standard Job Names

| job ID | `name` | 用途 |
|---|---|---|
| `security` | `Security scan (pre-commit)` | pre-commit によるシークレット検知・静的解析 |
| `lint` | `Lint` | コードスタイル・フォーマット検査 |
| `test` | `Test` / `Test (pytest)` など | ユニットテスト・インテグレーションテスト |
| `build`（任意） | `Build` | ビルド成果物の生成、またはインストール可能性の検証 |
| `gate` | ワークフロー自身の `name`（例：`CI`、`Dev Charter`） | 全 job の集約ゲート（後述）。必ず存在する |

`gate` は全 job の集約点として必ず最後に配置し、その `name` はワークフロー自身の `name`
（トップレベルの `name:`）と同じ文字列にする。Branch Protection（Ruleset）の必須ステータス
チェックには常にこの値（例：`ci.yml` なら `CI`）を登録する（`Build` ではない）。job 名に
`build` を使うのは、実際にビルド成果物を作る job（任意・実体のあるビルドがない場合は省略）だけ。

1リポジトリに複数のワークフローファイルがある場合（`ci.yml` と `dev-charter-check.yml` の
併用など）、各ワークフローの `name:` は互いに異なる値にする。`gate` の `name` をワークフロー
自身の `name` と一致させる規則により、複数の `gate` が同じチェック名を報告して Ruleset 上で
衝突する事態を自然に避けられる。

## Job Design

**CIのjob構成とRuleset設定を分離し、Ruleset管理を最小化する。**

- 集約ゲート `gate` job を必ず最後に配置し、`needs` で全依存を定義する
- 実体のあるビルド作業がある場合は `build` job を用意し、`gate` の `needs` に含める
- 単一job（lint/test 相当すら分けない極小プロジェクト）でも `gate` は省略しない。
  ビルド・検証の実処理をそのまま `gate` の中で行ってよい。lite 採用先はこの単一job
  構成（`security` job だけ、または `security` を `gate` に統合した最小構成）が多い
- Ruleset設定：ワークフロー自身の `name`（`gate` job の `name` と一致）のみ指定

この方針により、job を増減しても Ruleset の変更が不要になる（`gate` の `name` はワークフロー
自身の `name` に固定されており、job 構成の変更とは独立しているため）。

### `gate` Is a Gate, Not Just a `needs` Aggregation

> **注意（過去の誤り）:** 以前このドキュメントは、集約 job（当時は `build` という名前
> だった）について「いずれかの job が失敗すると skip され、マージ不可になる」と説明して
> いたが、これは誤り。GitHub の Ruleset / Branch Protection の `required_status_checks` は、
> 必須チェックが **`skipped` で完了した場合はブロックしない**（`failure` の場合のみ
> ブロックする）。集約 job が `needs: [security, lint, test]` のみで暗黙の `if: success()`
> に依存していると、依存 job が失敗したときに集約 job 自体は `skipped` として完了し、
> Ruleset 上は「必須チェックを満たした」と扱われて **失敗したままマージできてしまう**。
> 2026-08 に実際の運用で発覚した。

正しい実装は、`gate` を **常に実行するゲート job**（`if: always()`）にし、`needs.*.result`
を明示的に検査して `failure`/`cancelled` があれば自身を `failure` として終了させる。

```yaml
gate:
  name: CI   # ワークフロー自身の name: と同じ値にする
  needs: [security]   # lint/test/build 等があれば追加
  if: always()
  runs-on: ubuntu-latest   # ゲートは判定のみなので常に最安ランナーでよい
  steps:
    - name: Verify required jobs succeeded
      run: |
        for result in "${{ needs.security.result }}"; do
          if [ "$result" != "success" ]; then
            echo "::error::a required job did not succeed (got: $result)"
            exit 1
          fi
        done
```

### Cost Optimization (Path Filtering)

`docs/**` や `*.md` のみの変更（例：`git subtree pull` による dev-charter 更新、README
の修正）で `lint`/`test`/`build` のような高コストな job を持つ場合は、[dorny/paths-filter](https://github.com/dorny/paths-filter)
で変更内容を判定し job-level の `if:` でスキップする（full 側の
[CI_POLICY.md（full）の Cost Optimization](https://github.com/y-marui/dev-charter/blob/full/topics/CI_POLICY.md#cost-optimization-path-filtering)
にテンプレートあり）。`security` job（pre-commit）は安価な上、pre-commit 自身が変更ファイルに
応じて各フックを自動スキップするため、job 単位でのフィルタは不要。lite 採用先は
`security` だけの単一job構成が多く、その場合はこの節自体が不要（スキップすべき高コストな
job が無いため）。

### Concurrency (Cancel Superseded Runs)

同じブランチ/PRに素早く連続でpushすると、古いrunが完走するまで新しいrunと並行して
走り続け、Actions分・実時間を無駄に消費する。ワークフローのトップレベルに以下を追加し、
同一ワークフロー・同一refで新しいrunが始まったら古いrunを自動キャンセルする：

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

キャンセルされたrunは `cancelled` として終了するが、Ruleset の必須ステータスチェックは
常に最新commitのrunの結果だけを見るため、マージ可否の判定には影響しない。デメリットが
ないため、全ワークフローファイル（`ci.yml`・`dev-charter-check.yml` 等）に一律で追加する。

### Draft PRs

lite は「Require a pull request before merging」を OFF にする運用（[Branch Protection](#branch-protection-ruleset)参照）
だが、PRを経由する場合は full と同じくdraft PRの扱いに従う：`ready_for_review` を
`on.pull_request.types` に加えた上で、`security`・`gate` に draft スキップの `if:` を付ける。
デフォルトの `pull_request` トリガーは `opened`/`synchronize`/`reopened` のみで
`ready_for_review` を含まないため、これを忘れると draft 解除時に再実行されず、古い
（未評価の）ステータスのまま残ってしまう。

`.github/workflows/dev-charter-check.yml` も同様に draft をスキップする（[Version Check
(CI)](../README.md#version-check-ci) 参照）。`check-charter.yml` が作成する
`update-charter` PR も Draft で始まるため、この `ready_for_review` は更新 PR にも必須である。

**依存ロックファイル（`uv.lock` 等）は skip 対象に含めない。** ロックファイルの更新は
依存パッケージのバージョン変更そのものであり、実際に lint/test/build を回して初めて
壊れていないか確認できる。

### Artifact Retention

| 対象 | 保持期間（目安） |
|---|---|
| PR | 短期（例：7日） |
| main | 長期（例：30日） |

## Dependabot

`.github/dependabot.yml` の導入を検討する。依存パッケージがあるプロジェクトでは自動でアップデートPRを作成し、脆弱性対応を省力化できる。ドキュメントのみのリポジトリや依存パッケージが存在しないプロジェクトでは不要。

## Branch Protection (Ruleset)

**確認場所:** GitHub リポジトリ → Settings → Rules → Rulesets

Classic branch protection（Settings → Branches）ではなく **Ruleset** を使う。既存に Classic
branch protection が設定されている場合は削除し、下記の Ruleset を新規作成する（Classic と
Ruleset の使い分けの詳細は full 版の
[GITHUB_SETTINGS.md（full）](https://github.com/y-marui/dev-charter/blob/full/topics/GITHUB_SETTINGS.md)
の「Existing Ruleset Check」を参照）。

> **注意:** 「Require status checks to pass before merging」を ON にすると、「Require a
> pull request before merging」の ON/OFF に関わらず直接pushにも適用される。新規にpushする
> commitはpush時点でまだそのSHAに対する成功ステータスが存在しないため、bypassなしでは
> **直接pushそのものがブロックされてしまう**（`push` トリガーのCIも、ステータスが記録
> されるのはpush受理後になるため間に合わない）。「direct push許容」と「必須ステータス
> チェック」は、下記のようにオーナーをbypass actorにしない限り両立しない。

### Content

「Require a pull request before merging」は **OFFのまま**にして直接pushの余地を残しつつ、
リポジトリオーナー（実質1名の個人開発を想定）を bypass actor として登録する。bypassの
目的は「PR必須を免除する」ことではなく、**「Require status checks」が直接pushをブロック
してしまう副作用を、オーナーの分だけ打ち消す**こと。

```
Name: main-protection
Target: main
Enforcement: Active

Rules:
☐ Require a pull request before merging   （OFFのまま。直接pushを許可する）
☑ Require status checks to pass before merging
  └ Status checks: CI (GitHub Actions)
  └ Status checks: Dev Charter (GitHub Actions)   ← dev-charter-check.yml を導入している場合
☑ Block force pushes
☑ Restrict deletions

Bypass list:
  Repository admin — Bypass mode: Always
```

> **注意:** full 版のRulesetにある「Require conversation resolution before merging」は
> lite では設定できない。この設定は GitHub API 上 "Require a pull request before merging"
> のパラメータとしてのみ存在し、そのルール自体が「変更は必ずPR経由」を強制する一部のため、
> 「Require a pull request」をOFFにする lite の設計とは技術的に両立しない。lite では
> 会話解決の強制を諦め、direct push の余地を残すことを優先する。

full 版との差分は「Require a pull request before merging」をOFFにする点、「Require
conversation resolution before merging」を設定しない点、bypass actor（Repository admin,
mode: Always）を追加する点。

```json
{
  "actor_id": 5,
  "actor_type": "RepositoryRole",
  "bypass_mode": "always"
}
```

`actor_id: 5` は Repository admin ロール（個人リポジトリでは実質オーナー本人）。
`bypass_mode: "always"` は「この Ruleset のあらゆる制約を常にバイパスできる」ことを意味する
（full 版の[CI_POLICY.md（full）の Bypass Actor](https://github.com/y-marui/dev-charter/blob/full/topics/CI_POLICY.md#bypass-actor-repository-admin)
にある `bypass_mode: "pull_request"`（PR経由のマージ時のみ必須チェックをバイパスできるが
直接pushは引き続き禁止）よりも広い権限である点に注意）。

### Why a Bypass Actor Is Necessary

Ruleset自体には「直接pushは許可しつつ、PRを使う場合だけCIを必須にする」という中間モードは
存在しない。「Require a pull request before merging」をOFFにしても、他のルールが自動的に
直接pushへ適用されなくなるわけではなく、`Require status checks` は直接pushにも適用され続ける。
そして新規commitには push時点で成功ステータスが存在しないため、この設定単体では
**オーナーの直接pushすら拒否されてしまう**（上記の注意参照）。

そこで、オーナーだけを bypass actor（mode: always）にすることで、「オーナーは直接push
を含めて自由に運用できるが、それ以外（将来の共同作業者・Dependabot・`update-charter`
自動PR等）がPRを経由する場合は `Require status checks` が実際に効く」という状態を作る。
オーナー自身がPRを経由する場合も、bypass権限によりCI未通過のままマージすることは技術的
には可能だが、通常はCIグリーンを確認してからマージする運用とする。`pull_request` ルール
自体を持たないため、会話解決の強制はオーナー・非オーナーいずれについても働かない
（上記の注意参照）。

### Migration for Existing Adopters

Classic branch protection（`enforce_admins`・`required_conversation_resolution` 等）を
既に設定している採用先は、上記 Ruleset（オーナーのbypass actor登録を含む）への移行が
別途必要になる。

## Status Check Configuration

Rulesetの「Require status checks to pass before merging」でチェックを追加する際は、**名前とソースの両方を正しく指定**する。

**チェック名：**
GitHub Actions のステータスチェック名は、job の **`name` フィールドの値**（`gate` の場合、
ワークフロー自身の `name:` と同じ値。例：`CI`）で決まる。job ID（`gate`）ではないため注意。

```yaml
name: CI   # ワークフロー自身の name:

jobs:
  gate:
    name: CI   # ← Rulesetに登録する名前はこの値。ワークフローの name: と一致させる
```

job `name` を省略した場合は job ID がチェック名になる（例：`gate`）。

**ソース（Source）：**
チェック名を入力後、**ソースを `GitHub Actions` に指定する**（"Any source" のままにしない）。
"Any source" にすると、他の外部 CI サービスや手動操作でも条件を満たせてしまう。

Rulesetの設定画面では以下のように表示される：

```
Check name:  CI
Source:      GitHub Actions
```

集約ゲート job の `name` は説明を追加せず、常にそのワークフロー自身の `name:` と同じ値にする。個別 job の表示名は必要に応じて説明を追加してよい。
