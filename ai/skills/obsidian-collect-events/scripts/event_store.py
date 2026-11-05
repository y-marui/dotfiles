#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0.3,<7"]
# ///
"""Save an observed candidate with explicit identity and optimistic concurrency."""

import argparse
import contextlib
import datetime as dt
import json
import os
import re
import tempfile
import uuid
from pathlib import Path
from urllib.parse import urlparse

import yaml

FIELDS = {
    "record_id",
    "record_kind",
    "description",
    "name",
    "category",
    "date",
    "end_date",
    "time_text",
    "timezone",
    "venue",
    "region",
    "instruments",
    "works",
    "source_url",
    "official_url",
    "discovery_urls",
    "verification",
    "official_checked_on",
    "external_id",
    "center_id",
    "days",
    "start",
    "end",
    "note",
}
LISTS = {"instruments", "works", "discovery_urls", "days"}
STATES = {"unverified", "source_only", "official"}


class StoreError(ValueError):
    """Input or current state cannot be safely used."""


def date_string(value):
    if not isinstance(value, str) or dt.date.fromisoformat(value).isoformat() != value:
        raise StoreError("Dates must use YYYY-MM-DD")
    return value


def validate(data):
    uuid.UUID(data["record_id"])
    if data.get("record_kind") not in {"event", "circle"}:
        raise StoreError("record_kind must be event or circle")
    if data.get("verification") not in STATES:
        raise StoreError("Invalid verification state")
    for key in ["name", "description", "source_url"]:
        if not isinstance(data.get(key), str) or not data[key].strip():
            raise StoreError(f"Missing {key}")
    if data["record_kind"] == "event" and data.get("category") not in {
        "music",
        "art",
        "weekend",
        "sale",
        "screening",
    }:
        raise StoreError("Invalid event category")
    for key in FIELDS - LISTS:
        if key in data and not isinstance(data[key], str):
            raise StoreError(f"{key} must be a string")
    for key in LISTS:
        if key in data and (
            not isinstance(data[key], list)
            or any(not isinstance(item, str) for item in data[key])
        ):
            raise StoreError(f"{key} must be a list of strings")
    for key in ["source_url", "official_url"]:
        if key in data:
            url = urlparse(data[key])
            if url.scheme not in {"http", "https"} or not url.netloc:
                raise StoreError(f"Invalid {key}")
    for value in data.get("discovery_urls", []):
        url = urlparse(value)
        if url.scheme not in {"http", "https"} or not url.netloc:
            raise StoreError("Invalid discovery URL")
    for key in ["date", "end_date", "official_checked_on", "first_seen", "observed_on"]:
        if key in data:
            date_string(data[key])
    if data.get("end_date") and data.get("date") and data["end_date"] < data["date"]:
        raise StoreError("end_date precedes date")
    if data.get("first_seen", "") > data.get("observed_on", ""):
        raise StoreError("first_seen follows observation")
    if data.get("official_checked_on", "") > data.get("observed_on", ""):
        raise StoreError("Official check date follows observation")
    if data["verification"] == "official":
        if not data.get("official_url") or not data.get("official_checked_on"):
            raise StoreError("Official verification requires URL and check date")
    elif "official_checked_on" in data:
        raise StoreError("Non-official records cannot have an official check date")


def load(path):
    if path.is_symlink():
        raise StoreError("Candidate symlinks are not supported")
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\n(.*?)\n---(?:\n|$)", text, re.S)
    if not match:
        raise StoreError("Candidate has no YAML frontmatter")
    data = yaml.safe_load(match.group(1))
    if not isinstance(data, dict):
        raise StoreError("Candidate metadata is not an object")
    # Obsidian accepts unquoted dates; normalize those for comparisons/output.
    data = json.loads(json.dumps(data, default=lambda v: v.isoformat()))
    return data, text[match.end() :], text


def candidate_dir(root):
    path = root / "candidates"
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise StoreError("Candidate directory escapes the collection")
    return path


@contextlib.contextmanager
def locked(root):
    path = root / ".event-store.lock"
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise StoreError(
            "Another writer or stale lock exists; inspect before retry"
        ) from exc
    try:
        os.close(fd)
        yield
    finally:
        path.unlink()


def write_atomic(path, text):
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=".event-store-",
            suffix=".tmp",
            delete=False,
        ) as file:
            tmp = Path(file.name)
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.replace(tmp, path)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)


def put(root, fields, expected_revision, evidence, observed_on, dry_run=False):
    root = Path(root).resolve(strict=True)
    if not root.is_dir():
        raise StoreError("Collection must be a directory")
    if not isinstance(fields, dict) or set(fields) - FIELDS:
        raise StoreError(
            "Unknown candidate field; provide only documented public facts"
        )
    if type(expected_revision) is not int or expected_revision < 0:
        raise StoreError("expected_revision must be a nonnegative integer")
    if not evidence.strip():
        raise StoreError("Observation evidence is required")
    date_string(observed_on)
    fields = dict(fields)
    fields.setdefault("record_id", str(uuid.uuid4()))
    uuid.UUID(fields["record_id"])
    guard = contextlib.nullcontext() if dry_run else locked(root)
    with guard:
        directory = candidate_dir(root)
        entries = []
        for path in sorted(directory.glob("*.md")):
            data, body, raw = load(path)
            entries.append((path, data, body, raw))
        same = [e for e in entries if e[1].get("record_id") == fields["record_id"]]
        if len(same) > 1:
            raise StoreError("Duplicate record_id; reconcile manually")
        if same:
            path, old, body, raw = same[0]
            if old.get("revision") != expected_revision:
                raise StoreError("Revision conflict; reread before updating")
            if observed_on < old.get("observed_on", ""):
                raise StoreError("Observation is older than the current record")
            if fields.get("record_kind", old["record_kind"]) != old["record_kind"]:
                raise StoreError("Cannot change record_kind")
        else:
            if expected_revision != 0:
                raise StoreError("Missing record for requested revision")
            path = directory / (fields["record_id"] + ".md")
            old, body, raw = {}, "", None
        data = {**old, **fields}
        for key in fields:
            if fields[key] is None:
                data.pop(key, None)
        if "discovery_urls" in fields and fields["discovery_urls"] is not None:
            if not isinstance(fields["discovery_urls"], list) or any(
                not isinstance(value, str) for value in fields["discovery_urls"]
            ):
                raise StoreError("discovery_urls must be a list of strings")
            data["discovery_urls"] = sorted(
                set(old.get("discovery_urls", [])) | set(fields["discovery_urls"])
            )
        data.setdefault("verification", "unverified")
        data.setdefault("first_seen", observed_on)
        data["type"], data["observed_on"] = "source", observed_on
        validate(data)
        # Refuse exact identity collisions; the caller handles semantic matching.
        identity = ("record_kind", "name", "date", "time_text", "venue", "center_id")
        for other_path, other, _, _ in entries:
            if other_path != path and all(
                other.get(k) == data.get(k) for k in identity
            ):
                raise StoreError("Possible duplicate candidate; reuse its record_id")
        ignored = {"observed_on", "discovery_urls", "revision", "type"}
        changes = {
            k: {"before": old.get(k), "after": data.get(k)}
            for k in old.keys() | data.keys()
            if k not in ignored and old.get(k) != data.get(k)
        }
        material = bool(changes)
        data["revision"] = expected_revision + 1 if material else expected_revision
        if material:
            body += (
                f"\n## Observation revision {data['revision']} ({observed_on})\n\n"
                + evidence
                + "\n\n~~~json\n"
                + json.dumps(changes, ensure_ascii=False, sort_keys=True, indent=2)
                + "\n~~~\n"
            )
        text = (
            "---\n"
            + yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
            + "---\n"
            + body
        )
        if not dry_run:
            directory.mkdir(exist_ok=True)
            if raw is not None and path.read_text(encoding="utf-8") != raw:
                raise StoreError(
                    "File changed outside the lock; reread before updating"
                )
            write_atomic(path, text)
        return {
            "record_id": data["record_id"],
            "revision": data["revision"],
            "material_change": material,
            "dry_run": dry_run,
            "path": str(path),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collection", required=True, type=Path)
    parser.add_argument(
        "--input", required=True, type=Path, help="JSON candidate fields"
    )
    parser.add_argument("--expected-revision", required=True, type=int)
    parser.add_argument("--observed-on", required=True)
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        result = put(
            args.collection,
            json.loads(args.input.read_text(encoding="utf-8")),
            args.expected_revision,
            args.evidence,
            args.observed_on,
            args.dry_run,
        )
    except (StoreError, ValueError, KeyError, OSError, yaml.YAMLError) as exc:
        parser.exit(2, f"event-store: {exc}\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
