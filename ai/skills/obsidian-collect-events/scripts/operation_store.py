#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0.3,<7"]
# ///
"""Store recurring-source observations and notification state in an event vault."""

import argparse
import hashlib
import json
import re
import uuid
from pathlib import Path
from urllib.parse import urlparse

import yaml

from event_store import StoreError, date_string, load, locked, write_atomic

COLLECTIONS = {
    "sendaicmc": "areas/sendaicmc/information",
    "personal": "areas/culture/event-collection",
}
TRANSITIONS = {
    None: {"prepared"},
    "prepared": {"accepted", "failed", "unknown"},
    "unknown": {"accepted", "failed"},
    "accepted": {"delivered"},
    "failed": set(),
    "delivered": set(),
}


def scoped(vault, relative):
    path = vault
    for part in Path(relative).parts:
        path /= part
        if path.is_symlink():
            raise StoreError(f"Symlinks are not supported: {relative}")
    return path


def save(vault, relative, key, update, dry_run):
    directory = scoped(vault, relative)
    path = scoped(vault, f"{relative}/{key}.md")

    def plan():
        previous, body, _ = load(path) if path.exists() else ({}, "", "")
        record, body = update(previous, body)
        return (
            "---\n"
            + yaml.safe_dump(record, allow_unicode=True, sort_keys=False)
            + "---\n"
            + body
        )

    if dry_run:
        plan()
    else:
        directory.mkdir(parents=True, exist_ok=True)
        with locked(directory):
            write_atomic(path, plan())
    return str(path)


def observe(vault, collection, fields, evidence, dry_run=False):
    url = fields["source_url"]
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise StoreError("Source must have an HTTP(S) URL")
    if set(fields) != {
        "name",
        "source_url",
        "source_role",
        "coverage",
        "checked_on",
        "check_result",
    }:
        raise StoreError("Invalid source fields")
    if not isinstance(fields["name"], str) or not fields["name"].strip():
        raise StoreError("Source name is required")
    if not isinstance(fields["coverage"], list) or not all(
        isinstance(item, str) and item.strip() for item in fields["coverage"]
    ):
        raise StoreError("Coverage must be a list of strings")
    if fields["source_role"] not in {"discovery", "official"}:
        raise StoreError("Invalid source role")
    if fields["check_result"] not in {"ok", "partial", "failed", "not_checked"}:
        raise StoreError("Invalid check result")
    if not date_string(fields["checked_on"]) or not evidence.strip():
        raise StoreError("Observation requires a date and evidence")
    relative = f"{COLLECTIONS[collection]}/sources"
    directory = scoped(vault, relative)
    if not scoped(vault, f"{COLLECTIONS[collection]}/information.md").is_file():
        raise StoreError("Collection entry point is missing")
    with_existing = [
        p.stem for p in directory.glob("*.md") if load(p)[0].get("source_url") == url
    ]
    if len(with_existing) > 1:
        raise StoreError("Multiple sources have the same URL")
    key = next(iter(with_existing), hashlib.sha256(url.encode()).hexdigest())

    def update(previous, body):
        if previous and previous["source_url"] != url:
            raise StoreError("Source identity mismatch")
        if previous.get("checked_on", "") > fields["checked_on"]:
            raise StoreError("Observation predates the last check")
        record = {
            "type": "source",
            "record_kind": "discovery_source",
            "record_id": previous.get("record_id") or str(uuid.uuid4()),
            **previous,
            **fields,
        }
        if fields["check_result"] == "ok":
            record["last_success_on"] = fields["checked_on"]
        line = f"- {fields['checked_on']} [{fields['check_result']}] {' '.join(evidence.split())}"
        if not body:
            body = f"\n# {fields['name']}\n\n## 確認履歴\n"
        if line not in body.splitlines():
            body = body.rstrip() + "\n\n" + line + "\n"
        return record, body

    return save(vault, relative, key, update, dry_run)


def notify(vault, fields, expected, dry_run=False):
    task = fields["task"]
    run_date = fields["run_date"]
    key = fields["idempotency_key"]
    state = fields["send_state"]
    if task not in {"weekly-music-art-event", "weekly-sale-weekend-events"}:
        raise StoreError("Unknown task")
    if not date_string(run_date) or not re.fullmatch(
        re.escape(f"{task}-{run_date}") + r"(?:-[a-zA-Z0-9_-]+)?", key
    ):
        raise StoreError("Invalid notification key")
    versions = fields["event_versions"]
    if not isinstance(versions, list) or len(set(versions)) != len(versions):
        raise StoreError("Invalid event versions")
    for version in versions:
        identity, revision = version.split("@")
        uuid.UUID(identity)
        if not revision.isdecimal() or int(revision) < 1:
            raise StoreError("Invalid event revision")
    if set(fields) - {
        "task",
        "run_date",
        "idempotency_key",
        "event_versions",
        "send_state",
        "message_id",
        "accepted_at",
        "delivered_at",
    }:
        raise StoreError("Unexpected notification fields")
    if state not in {"accepted", "delivered"} and any(
        field in fields for field in ("message_id", "accepted_at", "delivered_at")
    ):
        raise StoreError("Receipt metadata requires an accepted notification")

    def update(previous, body):
        if previous.get("send_state") != expected or state not in TRANSITIONS.get(
            expected, set()
        ):
            raise StoreError("Notification state changed or transition is invalid")
        for field in (
            "task",
            "run_date",
            "idempotency_key",
            "event_versions",
            "message_id",
            "accepted_at",
        ):
            if (
                field in previous
                and fields.get(field, previous[field]) != previous[field]
            ):
                raise StoreError(f"Cannot change {field}")
        record = {
            "record_kind": "notification",
            "record_id": previous.get("record_id") or str(uuid.uuid4()),
            **previous,
            **fields,
        }
        if state in {"accepted", "delivered"} and not record.get("message_id"):
            raise StoreError("An accepted notification needs a receipt ID")
        if state == "delivered" and not record.get("delivered_at"):
            raise StoreError("Delivery needs a confirmed timestamp")
        if not body:
            body = f"\n# {task} {run_date}\n\n## 送信状態\n"
        return record, body.rstrip() + f"\n\n- {state}\n"

    filename = hashlib.sha256(key.encode()).hexdigest()
    return save(
        vault, "areas/digital-operations/event-notifications", filename, update, dry_run
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    subparsers = parser.add_subparsers(dest="kind", required=True)
    source = subparsers.add_parser("source")
    source.add_argument("--collection", required=True, choices=COLLECTIONS)
    source.add_argument("--evidence", required=True)
    notification = subparsers.add_parser("notification")
    notification.add_argument("--expected", choices=TRANSITIONS.keys() - {None})
    args = parser.parse_args()
    try:
        vault = args.vault.resolve(strict=True)
        if not (vault / "areas").is_dir():
            raise StoreError("Vault areas directory is missing")
        fields = json.loads(args.input.read_text(encoding="utf-8"))
        if args.kind == "source":
            path = observe(vault, args.collection, fields, args.evidence, args.dry_run)
        else:
            path = notify(vault, fields, args.expected, args.dry_run)
    except (ValueError, TypeError, KeyError, OSError, yaml.YAMLError) as exc:
        parser.exit(2, f"operation-store: {exc}\n")
    print(json.dumps({"path": path, "dry_run": args.dry_run}, ensure_ascii=False))


if __name__ == "__main__":
    main()
