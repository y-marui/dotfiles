---
name: format-glance-task-museum-events
description: "Audit, format, normalize, or reorder existing exhibition tasks in Glance Task's 「美術展: 関東」 and 「美術展: 東北」 groups through AppleScript, always checking unfinished tasks in both groups first. Use for canonicalizing exhibition titles, periods, or venues; finding format deviations; or restoring unfinished tasks to position order. When invoked without a target, repair every unambiguous finding in both groups without asking for confirmation. Do not use for creating a new exhibition task."
---

# Format Glance Task Museum Events

Use the bundled CLI to audit and format existing exhibitions through Glance Task's AppleScript commands. Identify tasks by stable ID and treat `task position`, never `fetch tasks` array order, as display order.

## Proceed Without Confirmation

- Treat a request to format, normalize, repair, or reorder as authorization to apply the requested changes. Do not pause for confirmation after the preflight or preview.
- When the user invokes this skill without specifying a task or narrower scope, repair every unambiguous format and order finding in both groups.
- Always run the non-applying preview internally, then continue directly with the identical `--apply` command when the result is unambiguous.
- If the user explicitly asks only to audit, inspect, check, or preview, do not apply changes.
- Ask only when required data is missing or ambiguous, such as malformed notes that do not determine complete dates and venue, duplicate exact titles, or a missing stable ID. Never guess.
- A task-specific request authorizes only that task and its group's order repair. Do not repair unrelated format findings unless the request covers all findings.

## Start With Both-Group Preflight

Before selecting or formatting a task, always fetch and audit both exhibition groups:

```bash
python3 <skill-dir>/scripts/museum_events.py preflight
```

- Check every unfinished top-level task in `美術展: 関東`, then `美術展: 東北`.
- Check notes against the canonical period-and-venue format.
- Check order by lexically sorting `task position`, then comparing against end date and start date order.
- Report format changes, format errors, and reorder requirements while continuing the authorized workflow; do not stop merely to request confirmation.
- For a task-specific request, treat problems in the other group as informative and do not mutate them. For an invocation without a target, repair all unambiguous findings in both groups.
- Stop if either group cannot be fetched or does not expose `task position`; never skip the failed group.

The `format` command performs this same two-group preflight internally and includes it in the preview and apply result. Do not bypass it by calling AppleScript directly.

## Resolve the Existing Task

After preflight, list the target group in real position order when needed to resolve the stable ID:

```bash
python3 <skill-dir>/scripts/museum_events.py list --group "美術展: 東北"
```

- Restrict mutations to `美術展: 関東` and `美術展: 東北`.
- Resolve an exact title to its stable task ID. Never use a partial title match. Ask if exact titles are duplicated.
- Preserve omitted fields and any existing trailing status emoji unless the user asks to change them.
- Refuse to format a subtask as a museum event.

## Format

Put the exhibition name in the title. Put exactly `<period> <venue>` in notes, using one ASCII space and two-digit month/day values.

```text
one day         YYYY/MM/DD 会場
same month      YYYY/MM/DD-DD 会場
same year       YYYY/MM/DD-MM/DD 会場
different years YYYY/MM/DD-YYYY/MM/DD 会場
```

Reject an end date before its start date. If existing notes are malformed, require the complete start date, end date, and venue instead of guessing missing fields.

## Format a Selected Task

Run the intended command without `--apply` first:

```bash
python3 <skill-dir>/scripts/museum_events.py format \
  --group "美術展: 東北" --task-id "<task-id>" \
  --start 2027/01/30 --end 2027/01/31 \
  --venue "せんだいメディアテーク"
```

Review the exact before/after values and desired order internally. Unless the user requested audit or preview only, rerun the identical command with `--apply` immediately when the result is unambiguous; do not ask for confirmation. Omit unchanged fields. Supplying no field changes canonicalizes the selected task's existing notes and repairs order.

## Format Every Finding

When no target is specified:

1. Run the mandatory preflight and collect every entry in `format_changes` for both groups.
2. For each stable task ID, run `format` without `--apply`, verify the exact before/after values, then run the identical command with `--apply` without pausing. Process mutations sequentially.
3. If a group still reports `needs_reorder`, run `sort --group <group> --apply`.
4. Run `preflight` again. Finish only when both groups have no `format_changes`, no `format_errors`, and `needs_reorder` is false, or report the exact ambiguous blocker.

Glance Task may expose updated `task position` values shortly after a reorder. If immediate verification reports a mismatch, fetch the group again before treating it as a failure; retry `sort` once if the refreshed audit still requires reordering.

## Audit or Repair One Group

Use a one-group audit only after the mandatory two-group preflight when investigating a specific finding:

```bash
python3 <skill-dir>/scripts/museum_events.py audit --group "美術展: 関東"
```

Repair only order:

```bash
python3 <skill-dir>/scripts/museum_events.py sort \
  --group "美術展: 関東" --apply
```

- Sort unfinished top-level tasks by end date, then start date, ascending.
- Preserve existing relative order for equal dates using `task position` as the tie-breaker.
- Leave completed tasks and subtasks unedited.
- Reorder through `reorder task ... after ...` and verify by fetching again and lexically sorting `task position`.
- Stop if any unfinished task is unparseable or `task position` is unavailable; never fall back to fetch order.

Report the task ID, exact before/after title and notes, and whether reordering occurred. Never create a new task from this skill; hand creation requests to the `add-glance-task-museum-event` skill.
