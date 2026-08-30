#!/usr/bin/env python3
"""Manage Glance Task museum-event lists through AppleScript."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, replace
from datetime import date
from pathlib import Path
from typing import Callable, Iterable, Sequence


APP_PATH = Path("/Applications/Glance Task.app")
SKILL_NAME = Path(__file__).resolve().parents[1].name
ALLOWED_GROUPS = ("美術展: 関東", "美術展: 東北")
RECORD_SEPARATOR = "\x1e"
FIELD_SEPARATOR = "\x1f"

# Trailing status emoji appended to a museum-event task title. ONGOING/BEFORE/ENDED
# are derived from today's date against the parsed period; FORMAT_ERROR marks a
# task whose notes could not be parsed. Order matters for stripping: longer or
# more specific matches are not a concern here since these are single emoji.
STATUS_EMOJI_ONGOING = "🎟️"
STATUS_EMOJI_BEFORE = "⏳"
STATUS_EMOJI_ENDED = "🏁"
STATUS_EMOJI_FORMAT_ERROR = "❌"
STATUS_EMOJIS = (
    STATUS_EMOJI_ONGOING,
    STATUS_EMOJI_BEFORE,
    STATUS_EMOJI_ENDED,
    STATUS_EMOJI_FORMAT_ERROR,
)


class MuseumEventError(RuntimeError):
    """A user-actionable validation or AppleScript error."""


@dataclass(frozen=True)
class EventPeriod:
    start: date
    end: date
    venue: str

    @property
    def notes(self) -> str:
        return format_notes(self.start, self.end, self.venue)


@dataclass(frozen=True)
class TaskRecord:
    task_id: str
    title: str
    notes: str | None
    completed: bool
    parent_id: str | None
    position: str | None


@dataclass(frozen=True)
class SortPlan:
    current: tuple[TaskRecord, ...]
    desired: tuple[TaskRecord, ...]

    @property
    def needs_reorder(self) -> bool:
        return tuple(task.task_id for task in self.current) != tuple(
            task.task_id for task in self.desired
        )


FETCH_TASKS_SCRIPT = r'''
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 1 then error "Expected one task group argument."
    set groupIdentifier to item 1 of argv
    tell application "/Applications/Glance Task.app"
        set fetchedTasks to fetch tasks from group groupIdentifier
    end tell

    set outputRows to {}
    repeat with taskReference in fetchedTasks
        set currentTask to contents of taskReference
        set notesText to task notes of currentTask
        if notesText is missing value then set notesText to ""
        set parentText to parent task id of currentTask
        if parentText is missing value then set parentText to ""
        set positionText to task position of currentTask
        if positionText is missing value then set positionText to ""
        set fieldValues to {(task id of currentTask), (task title of currentTask), notesText, ((task completed of currentTask) as text), parentText, positionText}
        repeat with fieldValue in fieldValues
            if (fieldValue as text) contains (character id 30) or (fieldValue as text) contains (character id 31) then error "A task field contains an unsupported control separator."
        end repeat
        set text item delimiters to character id 31
        set end of outputRows to fieldValues as text
    end repeat
    set text item delimiters to character id 30
    return outputRows as text
end run
end using terms from
'''

ADD_TASK_SCRIPT = r'''
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 3 then error "Expected group, title, and notes arguments."
    set groupIdentifier to item 1 of argv
    set titleText to item 2 of argv
    set notesText to item 3 of argv
    tell application "/Applications/Glance Task.app"
        return add task titleText to groupIdentifier notes notesText
    end tell
end run
end using terms from
'''

UPDATE_TASK_SCRIPT = r'''
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 4 then error "Expected group, task ID, title, and notes arguments."
    set groupIdentifier to item 1 of argv
    set targetTaskID to item 2 of argv
    set titleText to item 3 of argv
    set notesText to item 4 of argv
    tell application "/Applications/Glance Task.app"
        update task targetTaskID in group groupIdentifier title titleText notes notesText
    end tell
    return targetTaskID
end run
end using terms from
'''

REORDER_TASK_SCRIPT = r'''
using terms from application "/Applications/Glance Task.app"
on run argv
    if (count of argv) is not 3 then error "Expected group, task ID, and previous task ID arguments."
    set groupIdentifier to item 1 of argv
    set targetTaskID to item 2 of argv
    set previousTaskID to item 3 of argv
    tell application "/Applications/Glance Task.app"
        if previousTaskID is "" then
            reorder task targetTaskID in group groupIdentifier after missing value
        else
            reorder task targetTaskID in group groupIdentifier after previousTaskID
        end if
    end tell
    return targetTaskID
end run
end using terms from
'''

NOTIFY_SCRIPT = r'''
on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
end run
'''


def run_applescript(source: str, arguments: Sequence[str]) -> str:
    if not APP_PATH.is_dir():
        raise MuseumEventError(f"Glance Task is not installed at {APP_PATH}.")
    command = ["osascript", "-e", source, "--", *arguments]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired as error:
        raise MuseumEventError(
            "AppleScript timed out. Open Glance Task and check macOS Automation permission."
        ) from error
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "Unknown AppleScript error."
        raise MuseumEventError(message)
    return result.stdout.rstrip("\n")


def notify(title: str, message: str) -> None:
    """Best-effort macOS notification; failures here must not fail the caller."""
    try:
        subprocess.run(
            ["osascript", "-e", NOTIFY_SCRIPT, "--", title, message],
            check=False,
            capture_output=True,
            timeout=10,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


def fetch_tasks(group: str) -> list[TaskRecord]:
    raw = run_applescript(FETCH_TASKS_SCRIPT, [validate_group(group)])
    if not raw:
        return []
    records: list[TaskRecord] = []
    for index, row in enumerate(raw.split(RECORD_SEPARATOR), start=1):
        fields = row.split(FIELD_SEPARATOR)
        if len(fields) != 6:
            raise MuseumEventError(
                f"Unexpected AppleScript record {index}: expected 6 fields, got {len(fields)}."
            )
        task_id, title, notes, completed, parent_id, position = fields
        if completed not in {"true", "false"}:
            raise MuseumEventError(f"Unexpected completion value for task {task_id}: {completed}")
        records.append(
            TaskRecord(
                task_id=task_id,
                title=title,
                notes=notes or None,
                completed=completed == "true",
                parent_id=parent_id or None,
                position=position or None,
            )
        )
    return records


def validate_group(group: str) -> str:
    if group not in ALLOWED_GROUPS:
        allowed = " / ".join(ALLOWED_GROUPS)
        raise MuseumEventError(f"Group must be one of: {allowed}")
    return group


def clean_single_line(value: str, label: str) -> str:
    cleaned = value.strip()
    if not cleaned:
        raise MuseumEventError(f"{label} must not be empty.")
    if "\n" in cleaned or "\r" in cleaned or "\t" in cleaned:
        raise MuseumEventError(f"{label} must be a single line without tabs.")
    return cleaned


def parse_date(value: str, label: str) -> date:
    normalized = value.strip().replace("-", "/")
    parts = normalized.split("/")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise MuseumEventError(f"{label} must be YYYY/MM/DD or YYYY-MM-DD: {value}")
    try:
        return date(int(parts[0]), int(parts[1]), int(parts[2]))
    except ValueError as error:
        raise MuseumEventError(f"Invalid {label}: {value}") from error


def format_notes(start: date, end: date, venue: str) -> str:
    if end < start:
        raise MuseumEventError("The exhibition end date must not precede the start date.")
    clean_venue = clean_single_line(venue, "Venue")
    start_text = start.strftime("%Y/%m/%d")
    if end == start:
        period = start_text
    elif end.year != start.year:
        period = f"{start_text}-{end:%Y/%m/%d}"
    elif end.month != start.month:
        period = f"{start_text}-{end:%m/%d}"
    else:
        period = f"{start_text}-{end:%d}"
    return f"{period} {clean_venue}"


def parse_notes(notes: str | None) -> EventPeriod:
    if notes is None:
        raise MuseumEventError("notes are missing")
    if " " not in notes:
        raise MuseumEventError("notes must contain '<period> <venue>'")
    period_text, venue = notes.split(" ", 1)
    venue = clean_single_line(venue, "Venue")
    if "-" in period_text:
        start_text, end_text = period_text.split("-", 1)
    else:
        start_text = period_text
        end_text = None

    start_parts = start_text.split("/")
    if len(start_parts) != 3 or not all(part.isdigit() for part in start_parts):
        raise MuseumEventError("start date must be YYYY/MM/DD")
    try:
        start = date(*(int(part) for part in start_parts))
    except ValueError as error:
        raise MuseumEventError(f"invalid start date: {start_text}") from error

    if end_text is None:
        end = start
    else:
        end_parts = end_text.split("/")
        if not all(part.isdigit() for part in end_parts):
            raise MuseumEventError(f"invalid end date: {end_text}")
        try:
            if len(end_parts) == 1:
                end = date(start.year, start.month, int(end_parts[0]))
            elif len(end_parts) == 2:
                end = date(start.year, int(end_parts[0]), int(end_parts[1]))
            elif len(end_parts) == 3:
                end = date(*(int(part) for part in end_parts))
            else:
                raise MuseumEventError(f"invalid end date: {end_text}")
        except ValueError as error:
            raise MuseumEventError(f"invalid end date: {end_text}") from error
    if end < start:
        raise MuseumEventError("end date precedes start date")
    return EventPeriod(start=start, end=end, venue=venue)


def strip_status_emoji(title: str) -> str:
    stripped = title.rstrip()
    for emoji in STATUS_EMOJIS:
        if stripped.endswith(emoji):
            return stripped[: -len(emoji)].rstrip()
    return stripped


def status_emoji_for(period: EventPeriod, today: date) -> str:
    if today < period.start:
        return STATUS_EMOJI_BEFORE
    if today > period.end:
        return STATUS_EMOJI_ENDED
    return STATUS_EMOJI_ONGOING


def position_sorted(tasks: Iterable[TaskRecord]) -> tuple[TaskRecord, ...]:
    tasks_tuple = tuple(tasks)
    missing = [task.task_id for task in tasks_tuple if task.position is None]
    if missing:
        raise MuseumEventError(
            "Glance Task did not expose task position for: " + ", ".join(missing)
        )
    return tuple(sorted(tasks_tuple, key=lambda task: (task.position or "", task.task_id)))


def hierarchy_position_sorted(tasks: Iterable[TaskRecord]) -> tuple[TaskRecord, ...]:
    """Order top-level tasks and then each parent's children by sibling position."""
    tasks_tuple = tuple(tasks)
    top_level = position_sorted(task for task in tasks_tuple if task.parent_id is None)
    children_by_parent: dict[str, list[TaskRecord]] = {}
    for task in tasks_tuple:
        if task.parent_id is not None:
            children_by_parent.setdefault(task.parent_id, []).append(task)

    ordered: list[TaskRecord] = []
    placed: set[str] = set()
    for task in top_level:
        ordered.append(task)
        placed.add(task.task_id)
        children = position_sorted(children_by_parent.get(task.task_id, []))
        ordered.extend(children)
        placed.update(child.task_id for child in children)

    # Surface orphaned subtasks deterministically instead of silently dropping them.
    orphaned = [task for task in tasks_tuple if task.task_id not in placed]
    ordered.extend(
        sorted(
            orphaned,
            key=lambda task: (task.parent_id or "", task.position or "", task.task_id),
        )
    )
    return tuple(ordered)


def build_sort_plan(tasks: Iterable[TaskRecord]) -> SortPlan:
    unfinished = [task for task in tasks if not task.completed and task.parent_id is None]
    current = position_sorted(unfinished)
    parsed: dict[str, EventPeriod] = {}
    failures: list[str] = []
    for task in unfinished:
        try:
            parsed[task.task_id] = parse_notes(task.notes)
        except MuseumEventError as error:
            failures.append(f"{task.task_id} {task.title}: {error}")
    if failures:
        raise MuseumEventError(
            "Cannot sort until these unfinished top-level tasks are corrected:\n- "
            + "\n- ".join(failures)
        )
    desired = tuple(
        sorted(
            unfinished,
            key=lambda task: (
                parsed[task.task_id].end,
                parsed[task.task_id].start,
                task.position or "",
                task.task_id,
            ),
        )
    )
    return SortPlan(current=current, desired=desired)


def build_sort_plan_tolerant(tasks: Iterable[TaskRecord]) -> tuple[SortPlan, tuple[str, ...]]:
    """Like build_sort_plan, but tasks with unparsable notes sort last instead of
    blocking the whole plan. Returns the plan plus the task IDs that failed to parse."""
    unfinished = [task for task in tasks if not task.completed and task.parent_id is None]
    current = position_sorted(unfinished)
    parsed: dict[str, EventPeriod] = {}
    error_ids: list[str] = []
    for task in unfinished:
        try:
            parsed[task.task_id] = parse_notes(task.notes)
        except MuseumEventError:
            error_ids.append(task.task_id)

    def sort_key(task: TaskRecord) -> tuple:
        if task.task_id in parsed:
            period = parsed[task.task_id]
            return (0, period.end, period.start, task.position or "", task.task_id)
        return (1, date.max, date.max, task.position or "", task.task_id)

    desired = tuple(sorted(unfinished, key=sort_key))
    return SortPlan(current=current, desired=desired), tuple(error_ids)


def sort_payload(plan: SortPlan) -> dict[str, object]:
    def task_value(task: TaskRecord) -> dict[str, str]:
        period = parse_notes(task.notes)
        return {
            "task_id": task.task_id,
            "title": task.title,
            "notes": period.notes,
            "position": task.position or "",
        }

    return {
        "needs_reorder": plan.needs_reorder,
        "current": [task_value(task) for task in plan.current],
        "desired": [task_value(task) for task in plan.desired],
    }


def apply_sort(
    group: str,
    plan: SortPlan,
    rebuild_plan: Callable[[str], SortPlan] = lambda group: build_sort_plan(fetch_tasks(group)),
) -> bool:
    if not plan.needs_reorder:
        return False
    previous_task_id = ""
    for task in plan.desired:
        run_applescript(
            REORDER_TASK_SCRIPT,
            [group, task.task_id, previous_task_id],
        )
        previous_task_id = task.task_id
    verified = rebuild_plan(group)
    desired_ids = tuple(task.task_id for task in plan.desired)
    verified_ids = tuple(task.task_id for task in verified.current)
    if verified_ids != desired_ids:
        raise MuseumEventError(
            "Reorder verification failed. Expected "
            + repr(desired_ids)
            + ", got "
            + repr(verified_ids)
        )
    return True


def find_task(tasks: Iterable[TaskRecord], task_id: str) -> TaskRecord:
    matches = [task for task in tasks if task.task_id == task_id]
    if not matches:
        raise MuseumEventError(f"Task ID was not found in the selected group: {task_id}")
    return matches[0]


def resolve_format(
    task: TaskRecord,
    title: str | None,
    start_text: str | None,
    end_text: str | None,
    venue: str | None,
) -> TaskRecord:
    current_period: EventPeriod | None = None
    if start_text is None or end_text is None or venue is None:
        current_period = parse_notes(task.notes)
    new_title = clean_single_line(title, "Title") if title is not None else task.title
    new_start = (
        parse_date(start_text, "start date")
        if start_text
        else require_period(current_period).start
    )
    new_end = (
        parse_date(end_text, "end date")
        if end_text
        else require_period(current_period).end
    )
    new_venue = (
        clean_single_line(venue, "Venue")
        if venue is not None
        else require_period(current_period).venue
    )
    return replace(
        task,
        title=new_title,
        notes=format_notes(new_start, new_end, new_venue),
    )


def require_period(period: EventPeriod | None) -> EventPeriod:
    if period is None:
        raise MuseumEventError("Existing notes are required to preserve an omitted field.")
    return period


def replace_task(tasks: Iterable[TaskRecord], replacement: TaskRecord) -> list[TaskRecord]:
    return [replacement if task.task_id == replacement.task_id else task for task in tasks]


def command_list(args: argparse.Namespace) -> dict[str, object]:
    tasks = fetch_tasks(args.group)
    ordered = hierarchy_position_sorted(tasks)
    values = []
    for task in ordered:
        value: dict[str, object] = {
            "task_id": task.task_id,
            "position": task.position,
            "completed": task.completed,
            "parent_task_id": task.parent_id,
            "title": task.title,
            "notes": task.notes,
        }
        if task.notes:
            try:
                period = parse_notes(task.notes)
                value["canonical_notes"] = period.notes
                value["start"] = period.start.isoformat()
                value["end"] = period.end.isoformat()
            except MuseumEventError as error:
                value["format_error"] = str(error)
        values.append(value)
    return {"group": args.group, "tasks": values}


def audit_group(group: str) -> dict[str, object]:
    tasks = fetch_tasks(group)
    format_changes = []
    format_errors = []
    top_level = position_sorted(task for task in tasks if task.parent_id is None)
    for task in top_level:
        if task.completed:
            continue
        try:
            canonical = parse_notes(task.notes).notes
            if canonical != task.notes:
                format_changes.append(
                    {
                        "task_id": task.task_id,
                        "title": task.title,
                        "current_notes": task.notes,
                        "canonical_notes": canonical,
                    }
                )
        except MuseumEventError as error:
            format_errors.append(
                {"task_id": task.task_id, "title": task.title, "error": str(error)}
            )
    payload: dict[str, object] = {
        "group": group,
        "format_changes": format_changes,
        "format_errors": format_errors,
    }
    if not format_errors:
        payload["sort"] = sort_payload(build_sort_plan(tasks))
    return payload


def command_audit(args: argparse.Namespace) -> dict[str, object]:
    return audit_group(args.group)


def command_preflight(_args: argparse.Namespace) -> dict[str, object]:
    return {
        "groups": [audit_group(group) for group in ALLOWED_GROUPS],
    }


def command_sort(args: argparse.Namespace) -> dict[str, object]:
    plan = build_sort_plan(fetch_tasks(args.group))
    payload = {"group": args.group, "apply": args.apply, "sort": sort_payload(plan)}
    if args.apply:
        payload["reordered"] = apply_sort(args.group, plan)
    return payload


def command_add(args: argparse.Namespace) -> dict[str, object]:
    tasks = fetch_tasks(args.group)
    title = clean_single_line(args.title, "Title")
    duplicate_ids = [task.task_id for task in tasks if task.title == title]
    if duplicate_ids:
        raise MuseumEventError(
            "An exact-title task already exists; format it by stable ID instead: "
            + ", ".join(duplicate_ids)
        )
    start = parse_date(args.start, "start date")
    end = parse_date(args.end, "end date") if args.end else start
    notes = format_notes(start, end, args.venue)
    simulated = TaskRecord(
        task_id="<new-task>",
        title=title,
        notes=notes,
        completed=False,
        parent_id=None,
        position="~new",
    )
    preview = build_sort_plan([*tasks, simulated])
    payload: dict[str, object] = {
        "group": args.group,
        "apply": args.apply,
        "title": title,
        "notes": notes,
        "sort": sort_payload(preview),
    }
    if not args.apply:
        return payload

    created_id = run_applescript(ADD_TASK_SCRIPT, [args.group, title, notes])
    if not created_id:
        raise MuseumEventError("Glance Task returned an empty created task ID.")
    created_tasks = fetch_tasks(args.group)
    created = find_task(created_tasks, created_id)
    if created.title != title or created.notes != notes:
        raise MuseumEventError("The created task did not match the requested title and notes.")
    live_plan = build_sort_plan(created_tasks)
    payload["task_id"] = created_id
    payload["reordered"] = apply_sort(args.group, live_plan)
    return payload


def command_format(args: argparse.Namespace) -> dict[str, object]:
    preflight = command_preflight(argparse.Namespace())
    tasks = fetch_tasks(args.group)
    existing = find_task(tasks, args.task_id)
    if existing.parent_id is not None:
        raise MuseumEventError("Museum events must be top-level tasks; refusing to format a subtask.")
    updated = resolve_format(
        existing,
        title=args.title,
        start_text=args.start,
        end_text=args.end,
        venue=args.venue,
    )
    preview_tasks = replace_task(tasks, updated)
    preview = build_sort_plan(preview_tasks)
    payload: dict[str, object] = {
        "preflight": preflight,
        "group": args.group,
        "apply": args.apply,
        "task_id": existing.task_id,
        "before": {"title": existing.title, "notes": existing.notes},
        "after": {"title": updated.title, "notes": updated.notes},
        "sort": sort_payload(preview),
    }
    if not args.apply:
        return payload

    run_applescript(
        UPDATE_TASK_SCRIPT,
        [args.group, existing.task_id, updated.title, updated.notes or ""],
    )
    live_tasks = fetch_tasks(args.group)
    live = find_task(live_tasks, existing.task_id)
    if live.title != updated.title or live.notes != updated.notes:
        raise MuseumEventError("The updated task did not match the requested title and notes.")
    live_plan = build_sort_plan(live_tasks)
    payload["reordered"] = apply_sort(args.group, live_plan)
    return payload


@dataclass(frozen=True)
class FormatErrorInfo:
    task_id: str
    title: str
    error: str


@dataclass(frozen=True)
class GroupRefreshResult:
    group: str
    apply: bool
    retitled: tuple[tuple[str, str], ...]
    format_errors: tuple[FormatErrorInfo, ...]
    needs_reorder: bool
    reordered: bool


def refresh_group(group: str, today: date, apply: bool) -> GroupRefreshResult:
    """Non-interactive status-emoji refresh + reorder for one group.

    Unlike command_format/command_sort, this never blocks on unparsable notes:
    the offending task is marked with STATUS_EMOJI_FORMAT_ERROR and sorted last
    so the LaunchAgent-driven weekly run can keep going unattended."""
    tasks = fetch_tasks(group)
    top_level = [task for task in tasks if task.parent_id is None and not task.completed]

    retitled: dict[str, str] = {}
    format_errors: list[FormatErrorInfo] = []
    for task in top_level:
        base_title = strip_status_emoji(task.title)
        try:
            emoji = status_emoji_for(parse_notes(task.notes), today)
        except MuseumEventError as error:
            emoji = STATUS_EMOJI_FORMAT_ERROR
            format_errors.append(FormatErrorInfo(task.task_id, task.title, str(error)))
        new_title = f"{base_title} {emoji}"
        if new_title != task.title:
            retitled[task.task_id] = new_title

    if apply:
        for task in top_level:
            new_title = retitled.get(task.task_id)
            if new_title is not None:
                run_applescript(
                    UPDATE_TASK_SCRIPT,
                    [group, task.task_id, new_title, task.notes or ""],
                )
        tasks = fetch_tasks(group)

    plan, _ = build_sort_plan_tolerant(tasks)
    reordered = False
    if apply:
        reordered = apply_sort(
            group,
            plan,
            rebuild_plan=lambda g: build_sort_plan_tolerant(fetch_tasks(g))[0],
        )

    return GroupRefreshResult(
        group=group,
        apply=apply,
        retitled=tuple(retitled.items()),
        format_errors=tuple(format_errors),
        needs_reorder=plan.needs_reorder,
        reordered=reordered,
    )


def command_refresh(args: argparse.Namespace) -> dict[str, object]:
    today = date.today()
    results = [refresh_group(group, today, args.apply) for group in ALLOWED_GROUPS]
    format_errors = [
        {"group": result.group, "task_id": error.task_id, "title": error.title, "error": error.error}
        for result in results
        for error in result.format_errors
    ]
    if args.apply and format_errors:
        first = format_errors[0]
        summary = f"{first['group']}: {first['title']}"
        if len(format_errors) > 1:
            summary += f" ほか{len(format_errors) - 1}件"
        notify("美術展タスク: 書式エラーを検出", summary)
    return {
        "today": today.isoformat(),
        "groups": [
            {
                "group": result.group,
                "apply": result.apply,
                "retitled": [
                    {"task_id": task_id, "new_title": new_title}
                    for task_id, new_title in result.retitled
                ],
                "format_errors": [
                    {"task_id": error.task_id, "title": error.title, "error": error.error}
                    for error in result.format_errors
                ],
                "needs_reorder": result.needs_reorder,
                "reordered": result.reordered,
            }
            for result in results
        ],
        "format_errors": format_errors,
    }


def add_group_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--group", required=True, choices=ALLOWED_GROUPS)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List tasks in task-position order.")
    add_group_argument(list_parser)
    list_parser.set_defaults(handler=command_list)

    if SKILL_NAME == "glance-task-add-museum-event":
        add_parser = subparsers.add_parser("add", help="Add and position a museum event.")
        add_group_argument(add_parser)
        add_parser.add_argument("--title", required=True)
        add_parser.add_argument("--start", required=True)
        add_parser.add_argument("--end")
        add_parser.add_argument("--venue", required=True)
        add_parser.add_argument("--apply", action="store_true")
        add_parser.set_defaults(handler=command_add)

    else:
        preflight_parser = subparsers.add_parser(
            "preflight", help="Audit both museum-event groups before formatting."
        )
        preflight_parser.set_defaults(handler=command_preflight)

        audit_parser = subparsers.add_parser("audit", help="Audit notes and unfinished order.")
        add_group_argument(audit_parser)
        audit_parser.set_defaults(handler=command_audit)

        sort_parser = subparsers.add_parser("sort", help="Sort unfinished top-level tasks.")
        add_group_argument(sort_parser)
        sort_parser.add_argument("--apply", action="store_true")
        sort_parser.set_defaults(handler=command_sort)

        format_parser = subparsers.add_parser(
            "format", help="Format and reposition an existing museum event."
        )
        add_group_argument(format_parser)
        format_parser.add_argument("--task-id", required=True)
        format_parser.add_argument("--title")
        format_parser.add_argument("--start")
        format_parser.add_argument("--end")
        format_parser.add_argument("--venue")
        format_parser.add_argument("--apply", action="store_true")
        format_parser.set_defaults(handler=command_format)

        refresh_parser = subparsers.add_parser(
            "refresh",
            help=(
                "Non-interactive: update status emoji for both groups from today's "
                "date and reorder. Used by the museum-status-refresh LaunchAgent; "
                "not part of the interactive skill workflow."
            ),
        )
        refresh_parser.add_argument("--apply", action="store_true")
        refresh_parser.set_defaults(handler=command_refresh)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        payload = args.handler(args)
    except MuseumEventError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
