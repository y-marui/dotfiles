---
name: review-dotfiles-backup
description: "Audit the timestamped subdirectories under ~/.dotfiles-backup (the directory dotfiles' scripts/install.sh moves a file into whenever `make install` / `dots update` can't symlink over it) and decide, per entry, whether it holds information not already reflected in the dotfiles repo or the current live system state. If everything is redundant, hand the user the exact `rm -rf` command instead of running it. Use this whenever the user mentions ~/.dotfiles-backup, asks to check/clean up/prune dotfiles backups, or when `dots check` reports backup files accumulating there — don't just glance at file names and guess; actually compare content against the repo and live state before concluding anything is safe to discard."
---

# Review dotfiles backup

`scripts/install.sh` (and its PowerShell counterpart) creates `~/.dotfiles-backup/YYYYMMDDHHMMSS/` every time it needs to move a real file out of the way before replacing it with a symlink, or when it migrates something to a new dotfiles-managed location. Nobody deletes these afterward, so they accumulate for months. Your job is to look at what's actually in there and make a real decision per entry — not just report the file list back to the user.

## Why content review matters here

A file's *name* tells you almost nothing about whether it's safe to discard. `config.json` could be irreplaceable user configuration or it could be disposable app telemetry that regenerates on next launch. The only way to know is to compare it against the current dotfiles repo and the current live system. Don't skip this step even when a directory looks boringly repetitive (dozens of near-identical `Brewfile` snapshots, say) — confirm the pattern instead of assuming it from the first one or two.

## Step 1: Inventory

List every `~/.dotfiles-backup/YYYYMMDDHHMMSS/` directory and what each contains (`find ~/.dotfiles-backup -mindepth 2 | sort` is enough to start). Note the date range — if entries span many months, that's a sign this has never been cleaned up and the older ones almost certainly no longer matter.

## Step 2: Classify each entry, then verify the classification

Most entries fall into one of these buckets. State which bucket you think an entry is in, then actually check it before moving on — the check is the point, not the guess.

- **Stale snapshot of continuously-evolving state.** Homebrew `Brewfile` dumps, macOS Dock config (`dock-apps.txt`, `dock-sidebar.txt`, `dockfile.cache`), app state/telemetry files (`~/.claude.json`, `~/.codex/config.toml`), and similar. These files change on essentially every run by design, and the *current* live file or the version tracked in the dotfiles repo is authoritative — a backup is by definition older and gets superseded. Confirm this by diffing the backup against the current tracked/live equivalent rather than assuming; if it turns out the backup has something the current version lacks, it's not actually stale and needs a closer look.
- **Migration leftover, already landed.** A file or directory that was moved aside during a restructuring (e.g. an agent skill relocated into `ai/skills/`). Check whether the equivalent now exists correctly in the dotfiles repo, or as a working symlink from it. If so, the backup copy is a redundant leftover from a successful migration.
- **Migration leftover, deliberately excluded.** Sometimes what got moved aside was never meant to be dotfiles-managed in the first place — e.g. a third-party or marketplace-installed skill that isn't part of this repo's own `ai/skills/`. Confirm it's genuinely absent from the repo (not just absent from where you expected it) before calling it correctly-excluded rather than lost.
- **Genuinely obsolete artifact.** Regenerable caches (shell completion dumps, etc.) or symlinks that point at a dotfiles path which no longer exists (renamed/restructured since). Safe to discard once confirmed the target really is gone or superseded.

## Step 3: Handle credentials carefully

Config files for AI tools and other apps (`~/.claude.json`, `~/.codex/config.toml`, and similar) routinely embed live OAuth bearer tokens, API keys, or other secrets for MCP servers and integrations — right next to the harmless preference data. **Never `cat` or otherwise dump the full contents of a file like this into your output.** Use targeted comparisons instead:

- `diff` the backup against the current live file, or a JSON-parsed key comparison (e.g. `python3 -c "import json; ..."` to check specific keys like `mcpServers` without printing the whole structure)
- `grep` for the specific field you care about
- Compare key lists (`.keys()`) before comparing values

If you do accidentally print something that looks like a live token or credential, stop and tell the user immediately so they can rotate it — don't just quietly move on.

## Step 4: Decide and act

- **If something is genuinely unique and worth keeping**: incorporate it into the dotfiles repo the normal way — edit the relevant tracked file, or explain clearly why it doesn't actually belong there if it turns out to be host-specific or otherwise out of scope. Don't just copy the raw backup file back into place without understanding what it represents.
- **If everything checked out as redundant or obsolete**: summarize what you checked and why each category was safe to discard. Then give the user the exact command to run themselves:

  ```bash
  rm -rf ~/.dotfiles-backup
  ```

  Do not run this yourself. Permanently deleting data is something only the user does, regardless of how confident the analysis is or whether they've already said "just delete it" — state the rule and hand them the command.

## Reporting back

Tell the user, per category, roughly how many entries fell into it and what you concluded — not a blow-by-blow of every `find`/`diff` command. If you found something worth keeping, say specifically what you did with it (which file you edited, and why).
