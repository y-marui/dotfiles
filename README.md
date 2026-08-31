# Dev Charter (lite)

> **This is the reference (English) version.**
> For the canonical (Japanese) version, see [README-jp.md](README-jp.md).

The **lite** variant of [dev-charter](https://github.com/y-marui/dev-charter):
only the parts that are universally valuable regardless of project type (AI
context maintenance, task management via GitHub Issues/Projects, secrets
management, etc.). Software-project-specific content (Python dev environment,
UI design, monetization policy, and so on) is not included. See
[CHARTER_INDEX.md](CHARTER_INDEX.md) for what's included. If you need that
content, consider the `full` branch instead.

## Install (git subtree)

```
git remote add dev-charter https://github.com/y-marui/dev-charter
git fetch dev-charter
git subtree add --prefix=docs/dev-charter dev-charter lite --squash
```

After installing, paste the following prompt into your AI tool:

```
Read docs/dev-charter/CHARTER_INDEX.md and set up AI_CONTEXT.md etc. for this project
```

The Quick Install one-liner does the same thing:

```bash
CHARTER_BRANCH=lite bash <(curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh)
```

## Update

Re-running the Quick Install one-liner also works for updates — it detects
the existing install and its branch (here, lite), then runs `git subtree
pull` for you (stashing/restoring uncommitted changes as needed, and falling
back to a full re-sync for template-repo checkouts):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh)
```

To update manually instead: if the `dev-charter` remote is not set up (e.g., after cloning the project), add it first:

```
git remote add dev-charter https://github.com/y-marui/dev-charter
git subtree pull --prefix=docs/dev-charter dev-charter lite --squash
```

> **Note (projects created from a template repository):**
> GitHub templates copy files only — git history is not carried over — so `git subtree pull` will fail.
> The `check-charter.yml` workflow detects this automatically and handles it.
> For manual updates, use the following instead of `git subtree pull`:
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

After updating, run `git diff HEAD~1 HEAD --name-only -- docs/dev-charter/`
to see what changed and have your AI tool apply it to the project (lite
doesn't have its own `UPDATE_CHECKLIST.md`).

## Version Check (CI)

Add `.github/workflows/dev-charter-check.yml` to your project to check for
updates when a PR is opened or a commit is pushed to main, and open an
update PR if outdated (the check is skipped if one already succeeded
within the last 7 days, so busy repos don't re-check on every single
event). **Tracking lite requires setting `branch: lite` explicitly**:

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

> **Note:** Omitting `with: branch: lite` makes it track `full`'s default
> instead, so it'll keep flagging this project as outdated (or up to date
> when it isn't) because full's and lite's VERSION values diverge.
> `check-charter.yml` itself also detects a mismatch between the installed
> `docs/dev-charter/CHARTER_INDEX.md` variant and the `branch` input and
> errors out.

> **Note:** `check` is skipped for Dependabot PRs and draft PRs (see below). `gate`
> treats a `skipped` result as fine in both cases and always reports a `Dev Charter`
> status (matching this workflow's own `name:`). Register `Dev Charter` — not `Check /
> check` — as the required status check in Branch Protection (Ruleset); see
> [CI_POLICY.md's Ruleset section](topics/CI_POLICY.md#branch-protection-ruleset).
> Registering the `check` job itself is unsafe: when it's skipped, the `Check / check`
> context is never reported at all, so the PR sits at "Expected — Waiting for status to
> be reported" forever.

> **Note:** Dependabot PRs are skipped — dependency-only activity doesn't warrant a
> charter check. If your repository goes fully quiet, no check will run. If you want a
> guaranteed periodic check regardless of activity, add a low-frequency `schedule`
> (e.g. monthly) alongside this.

> **Note:** Draft PRs are skipped (a draft can't be merged anyway, so there's no risk
> in leaving the check unreported). `ready_for_review` in `on.pull_request.types` makes
> sure taking a PR out of draft re-triggers a real run.

> **Note:** If your repository has Branch Protection rules that prevent direct pushes,
> add a bypass rule for the GitHub Actions bot
> (Settings > Rules > Rulesets > Bypass list > GitHub Actions).

## Makefile helper

`git subtree pull` fails if the working tree has uncommitted changes, so this
target automatically stashes before running and pops afterward.

This target doesn't need to remember whether you installed `full` or `lite`
(or another distribution branch added later). It auto-detects the installed
branch every time from the existing `docs/dev-charter/CHARTER_INDEX.md`'s
`# Charter Index (<branch>)` marker (generated by `scripts/publish-branch.sh`;
absence of a marker means `full`), which prevents the accident of updating a
full install with lite or vice versa.

```
.PHONY: update-charter
update-charter:
	CHARTER_UPDATE_ONLY=1 bash <(curl -fsSL https://raw.githubusercontent.com/y-marui/dev-charter/main/scripts/install.sh)
```

`CHARTER_UPDATE_ONLY=1` means that if this target is ever run before
anything is installed, it won't silently install `full` — it asks which
branch you want instead (or errors out with guidance in a non-interactive
environment).

## Badge for Adopting Projects

Place this badge in your project README to show dev-charter update health.

```markdown
[![Charter Check](https://github.com/{owner}/{repo}/actions/workflows/dev-charter-check.yml/badge.svg)](https://github.com/{owner}/{repo}/actions/workflows/dev-charter-check.yml)
```

Replace `{owner}` and `{repo}` with your GitHub organization and repository name.

| State | Status Badge |
|---|---|
| Not installed / CI not set up | red (VERSION not found) |
| Installed, up to date | green |
| Installed, outdated | red |

---

*This document has a Japanese canonical version [README-jp.md](README-jp.md). Update both in the same commit when editing.*
