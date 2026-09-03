# GitHub Repository Settings (lite)

個人開発〜小規模で、`main` への直接pushを許可するプロジェクト向けの GitHub リポジトリ設定ガイド。Sponsors・CODEOWNERSなど、外部コントリビューターの受け入れやOSS運用を前提とした項目は full 版の [GITHUB_SETTINGS.md（full）](https://github.com/y-marui/dev-charter/blob/full/topics/GITHUB_SETTINGS.md)を参照する。

## AI-Driven Configuration

各セクションには `gh` コマンドまたは設定ファイルを記載している。AI がセットアップ・更新作業を行う場合は以下の方針で適用する。

- `gh` コマンドが使える場合（CLI 環境）：記載のコマンドを実行する
- `gh` が使えない場合（GitHub Copilot・ブラウザ操作など）：「確認場所」の UI パスから手動で設定する
- どちらの場合も、**設定を適用すること自体は必須**。コマンドが使えないことを理由にスキップしない

## Repository Features

**確認場所:** GitHub リポジトリ → Settings → General → Features

### Wikis

**設定値: ON（必ず有効にする）**

```bash
gh api -X PATCH repos/{owner}/{repo} -F has_wiki=true
```

### Projects

**設定値: ON（必ず有効にする）**

```bash
gh api -X PATCH repos/{owner}/{repo} -F has_projects=true
```

> Issues・Discussions は本ドキュメントで統一値を定めない（プロジェクトごとに要否が異なるため）。Sponsorships は full 版の [Sponsors (FUNDING.yml)](https://github.com/y-marui/dev-charter/blob/full/topics/GITHUB_SETTINGS.md#sponsors-fundingyml) で統一値を定めている（テンプレートリポジトリのみ OFF、それ以外は public/private を問わず ON）。

## Direct Push vs. Pull Request

lite の運用では、変更の大部分は `main` への直接pushで完結させ、一部の大きな変更だけPRを経由する。判断に迷う場合はPRを経由する側に倒す。

| 直接pushでよい | PR経由にする |
|---|---|
| 依存関係定義ファイル・設定ファイルの追従的な更新（Brewfile、lockファイルの通常更新等） | 新規スクリプトの追加、既存スクリプトの大規模な見直し・書き換え |
| ノート・メモ・コンテキストファイルの蓄積、既存ドキュメントの軽微な修正 | 新規 Agent Skill の追加、既存 Skill の大規模改修 |
| 既存 Skill・ドキュメントの軽微なブラッシュアップ、typo修正 | プロジェクト全体構造（ディレクトリ構成、AIコンテキスト階層等）に関わる refactoring |

## Branch Protection (Ruleset)

[CI_POLICY.md（lite）](https://github.com/y-marui/dev-charter/blob/lite/topics/CI_POLICY.md)
の「Branch Protection (Ruleset)」で定義した Ruleset が正しく設定されているか確認する。

**確認場所:** GitHub リポジトリ → Settings → Rules → Rulesets

### Existing Ruleset Check

既存の設定状態に応じて対応が異なる（full 版と同じ判断基準。詳細は full 版の
[GITHUB_SETTINGS.md（full）の Existing Ruleset Check](https://github.com/y-marui/dev-charter/blob/full/topics/GITHUB_SETTINGS.md#existing-ruleset-check)参照）：

| 状態 | 対応 |
|---|---|
| `main-protection` が存在する | 下記チェックリストで内容を確認する |
| 別名（`main`・`branch-protection` 等）の Ruleset が存在する | `main-protection` に改名し、内容を確認する |
| Classic branch protection が設定されている | 削除して `main-protection` Ruleset を新規作成する（Classic は機能が限定的） |
| 何も設定されていない | `main-protection` Ruleset を新規作成する |

### Content Checklist

設定値・ルール一覧は
[CI_POLICY.md（lite）の Branch Protection (Ruleset)](https://github.com/y-marui/dev-charter/blob/lite/topics/CI_POLICY.md#branch-protection-ruleset)
を参照。

確認ポイント：

- `Enforcement` が `Active` になっているか（`Evaluate` / `Disabled` は機能しない）
- Status check のソースが `GitHub Actions` に設定されているか（`Any source` にしない）
- Bypass list に Repository admin（mode: Always）が登録されているか

## Pull Request Merging

**確認場所:** GitHub リポジトリ → Settings → General → Pull Requests

### Automatically Delete Head Branches

**設定値: ON（必ず有効にする）**

PR マージ後にリモートブランチを自動削除する。マージ済みブランチが蓄積してリポジトリが汚れるのを防ぐ。

```bash
gh api -X PATCH repos/{owner}/{repo} -f delete_branch_on_merge=true
```

> 誤って削除した場合は、マージ直後に限り GitHub の "Restore branch" ボタンから復元できる。

### Allow Auto-merge

**設定値: ON（必ず有効にする）**

PR がすべてのステータスチェックを通過したとき自動マージできる機能を有効にする。Dependabot PR などの bot が作成する PR を自動処理する際に有用。

```bash
gh api -X PATCH repos/{owner}/{repo} -F allow_auto_merge=true
```

> この設定を ON にしても各 PR が自動でマージされるわけではない。PR ごとに "Enable auto-merge" を選択した場合のみ自動マージが走る。
>
> **注意:** Private リポジトリのうち、個人アカウントの通常の private リポジトリより
> 制限が強い環境（例：private Organization が所有する private リポジトリの fork）
> では、この設定が API 経由で `true` にならないことがある（エラーは返らず黙って
> `false` のまま）。[main-protection Ruleset](#branch-protection-ruleset)と同様の
> プラン・権限制限が疑われるが未確認。該当する場合は無理に追わず、既知の制限として
> 記録だけして先送りしてよい。

## Actions: Workflow permissions

**確認場所:** GitHub リポジトリ → Settings → Actions → General → Workflow permissions

### Workflow Permissions

**設定値:** `Read repository contents and packages permissions`（デフォルト）のまま使う。

リポジトリレベルの権限は Read only のままにしておき、書き込みが必要なワークフローでは workflow ファイル内で `permissions` を個別に指定する。

```yaml
# 例: update-version.yml でコミット・プッシュする場合
permissions:
  contents: write
```

個別指定はリポジトリのデフォルト設定より優先されるため、グローバルを変更する必要はない。

### Allow GitHub Actions to create and approve pull requests

**設定値:** dev-charter を導入するリポジトリでは **ON にする**。

`check-charter.yml` は `gh pr create` でプルリクエストを作成するため、このチェックボックスが OFF のままだとワークフローが失敗する。

```bash
gh api -X PUT repos/{owner}/{repo}/actions/permissions/workflow \
  -F can_approve_pull_request_reviews=true
```

> このチェックボックスはリポジトリ作成時にデフォルトで OFF。`check-charter.yml` を導入する際は必ず ON になっているか確認すること。

## Actions: Allowed Actions and Reusable Workflows

**確認場所:** GitHub リポジトリ → Settings → Actions → General → Actions permissions

**設定値:** `Allow y-marui, and select non-y-marui, actions and reusable workflows`
（API では `allowed_actions: "selected"`）にする。デフォルトの `Allow all actions and
reusable workflows` のままにせず、そのリポジトリの `.github/workflows/*.yml` が実際に
使う非 `actions/*` の Action・reusable workflow だけを明示許可する。

`actions/*`（GitHub 公式所有）は `github_owned_allowed: true` で自動的に許可されるため
個別指定は不要。`y-marui/*` の Action・reusable workflow（同一オーナーの別リポジトリ）は
`github_owned_allowed`ではカバーされないため、`patterns_allowed` へ明示的に列挙する。

```bash
gh api --method PUT repos/{owner}/{repo}/actions/permissions \
  -F enabled=true -f allowed_actions=selected

gh api --method PUT repos/{owner}/{repo}/actions/permissions/selected-actions \
  --input - <<'EOF'
{
  "github_owned_allowed": true,
  "verified_allowed": false,
  "patterns_allowed": [
    "pre-commit/action@v3.0.1",
    "y-marui/dev-charter/.github/workflows/check-charter.yml@main"
  ]
}
EOF
```

`patterns_allowed` の内容はリポジトリごとに異なる。全ワークフローファイルの `uses:` 行から
`actions/*` 以外（実際に使っているものだけ）を集めて列挙する。

> **重要な運用上の注意:** ワークフローに新しい非 `actions/*` Action を追加したら、**push
> する前に** `patterns_allowed` へそのAction（`owner/repo@ref` の形）を追加すること。許可
> リストの更新より先に push すると、そのワークフロー実行全体が `startup_failure`（ジョブの
> エラーではなく「ワークフローファイルの問題」とだけ報告され、原因が分かりにくい）になる。
> 既存の失敗した実行は再実行（rerun）できないため、許可リストを直してから空コミット等で
> 改めて push し直す必要がある。

## Issue Auto-assign

リポジトリオーナーが Issue を作成したときに自動で自分にアサインする。
GitHub Dashboard の "Assigned to me" に即座に表示されるようになる。

**ファイルパス:** `.github/workflows/auto-assign-self.yml`

```yaml
name: Assign self when I create an issue

on:
  issues:
    types: [opened, reopened]

jobs:
  assign:
    if: github.actor == github.repository_owner || endsWith(github.actor, '[bot]')
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/github-script@v9
        with:
          script: |
            await github.rest.issues.addAssignees({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              assignees: [context.repo.owner],
            })
```

`github.repository_owner` を使うことでユーザー名のハードコードが不要。
他者が Issue を作成した場合は `if` 条件が false になりスキップされる。

## Security & Analysis

**確認場所:** GitHub リポジトリ → Settings → Security & analysis

### Dependabot Alerts

**設定値: ON**

脆弱性のある依存パッケージを検出して通知する。パブリック・プライベートリポジトリ問わず無料。

```bash
gh api -X PUT repos/{owner}/{repo}/vulnerability-alerts
```

### Dependabot Security Updates

**設定値: ON**

Dependabot が脆弱性を検出したとき、修正 PR を自動作成する。

```bash
gh api -X PUT repos/{owner}/{repo}/automated-security-fixes
```

### Secret Scanning & Push Protection

**設定値: ON**

コミット・コードにシークレット（API キー等）が含まれていないか検出する。Push protection は push 時点でブロックする。

```bash
gh api -X PATCH repos/{owner}/{repo} \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
```

> **注意:** プライベートリポジトリでの secret scanning は GitHub Advanced Security が必要（有料）。パブリックリポジトリは無料で使用できる。
