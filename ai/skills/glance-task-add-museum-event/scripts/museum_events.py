#!/usr/bin/env python3
"""Manage Glance Task museum-event lists through AppleScript."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass, replace
from datetime import date
from pathlib import Path
from typing import Iterable, Sequence


APP_PATH = Path("/Applications/Glance Task.app")
SKILL_NAME = Path(__file__).resolve().parents[1].name
ALLOWED_GROUPS = ("美術展: 関東", "美術展: 東北")
RECORD_SEPARATOR = "\x1e"
FIELD_SEPARATOR = "\x1f"


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
    if (count of argv) is not 4 then error "Expected group, title, notes, and previous task ID arguments."
    set groupIdentifier to item 1 of argv
    set titleText to item 2 of argv
    set notesText to item 3 of argv
    set previousTaskID to item 4 of argv
    tell application "/Applications/Glance Task.app"
        if previousTaskID is "" then
            return add task titleText to groupIdentifier notes notesText
        else
            return add task titleText to groupIdentifier notes notesText after previousTaskID
        end if
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


def apply_sort(group: str, plan: SortPlan) -> bool:
    if not plan.needs_reorder:
        return False
    previous_task_id = ""
    for task in plan.desired:
        run_applescript(
            REORDER_TASK_SCRIPT,
            [group, task.task_id, previous_task_id],
        )
        previous_task_id = task.task_id
    verified = build_sort_plan(fetch_tasks(group))
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


def previous_task_id(plan: SortPlan, target_task_id: str) -> str | None:
    desired_ids = tuple(task.task_id for task in plan.desired)
    try:
        target_index = desired_ids.index(target_task_id)
    except ValueError as error:
        raise MuseumEventError(
            f"The target task is missing from the desired position order: {target_task_id}"
        ) from error
    if target_index == 0:
        return None
    return desired_ids[target_index - 1]


def verify_direct_insert(
    group: str,
    created_id: str,
    title: str,
    notes: str,
    expected_ids: tuple[str, ...],
) -> TaskRecord:
    last_ids: tuple[str, ...] = ()
    for attempt in range(3):
        created_tasks = fetch_tasks(group)
        created = find_task(created_tasks, created_id)
        if created.title != title or created.notes != notes:
            raise MuseumEventError("The created task did not match the requested title and notes.")
        live_plan = build_sort_plan(created_tasks)
        last_ids = tuple(task.task_id for task in live_plan.current)
        if last_ids == expected_ids and not live_plan.needs_reorder:
            return created
        if attempt < 2:
            time.sleep(1)
    raise MuseumEventError(
        "Direct insertion verification failed. Expected "
        + repr(expected_ids)
        + ", got "
        + repr(last_ids)
    )


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
    existing_plan = build_sort_plan(tasks)
    if existing_plan.needs_reorder:
        raise MuseumEventError(
            "Existing unfinished tasks are out of position order; repair the group with "
            "$glance-task-format-museum-events before adding a new event."
        )
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
    insert_after_task_id = previous_task_id(preview, simulated.task_id)
    payload: dict[str, object] = {
        "group": args.group,
        "apply": args.apply,
        "title": title,
        "notes": notes,
        "insert_after_task_id": insert_after_task_id,
        "sort": sort_payload(preview),
    }
    if not args.apply:
        return payload

    created_id = run_applescript(
        ADD_TASK_SCRIPT,
        [args.group, title, notes, insert_after_task_id or ""],
    )
    if not created_id:
        raise MuseumEventError("Glance Task returned an empty created task ID.")
    expected_ids = tuple(
        created_id if task.task_id == simulated.task_id else task.task_id
        for task in preview.desired
    )
    created = verify_direct_insert(args.group, created_id, title, notes, expected_ids)
    payload["task_id"] = created_id
    payload["position"] = created.position
    payload["inserted_in_position"] = True
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
