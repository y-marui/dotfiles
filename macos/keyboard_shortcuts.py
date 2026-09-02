#!/usr/bin/env python3
"""Manage macOS application-shortcut preferences without replacing other defaults.

The managed file is stored in the sibling dotfiles-private repository.  Each
entry maps a preferences domain and menu-item title to its NSUserKeyEquivalent.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


KEY = "NSUserKeyEquivalents"
GLOBAL_DOMAIN = "NSGlobalDomain"
SCHEMA_VERSION = 1


def dotfiles_dir() -> Path:
    configured = os.environ.get("DOTFILES_DIR")
    if configured:
        return Path(configured).resolve()
    return Path(__file__).resolve().parent.parent


def private_dir() -> Path:
    public = dotfiles_dir()
    return public.with_name(f"{public.name}-private")


def managed_path() -> Path:
    return private_dir() / "macos" / "keyboard-shortcuts.plist"


def cache_path() -> Path:
    return private_dir() / "macos" / "keyboard-shortcuts.cache.plist"


def run_defaults(*arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["defaults", *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )


def export_domain(domain: str) -> dict[str, Any] | None:
    result = run_defaults("export", domain, "-")
    if result.returncode != 0 or not result.stdout:
        return None
    try:
        value = plistlib.loads(result.stdout)
    except (plistlib.InvalidFileException, ValueError):
        # Some domains contain malformed sentinel dates (e.g. year 0000, seen in
        # com.apple.stocks.widget / com.microsoft.autoupdate2) that plistlib
        # cannot parse; treat those domains as unreadable rather than aborting.
        return None
    return value if isinstance(value, dict) else None


# CoreFoundation pseudo-domain identifiers. Sandboxed apps sometimes surface a
# container-local file literally named after one of these (e.g.
# .../com.apple.SiriNCService/.../kCFPreferencesAnyApplication.plist), which
# mirrors NSGlobalDomain rather than being a distinct real domain.
CF_PSEUDO_DOMAINS = {
    "kCFPreferencesAnyApplication",
    "kCFPreferencesCurrentApplication",
    "kCFPreferencesAnyHost",
    "kCFPreferencesCurrentHost",
}


def preference_domains() -> list[str]:
    result = run_defaults("domains")
    domains = {GLOBAL_DOMAIN}
    if result.returncode == 0:
        domains.update(domain.strip() for domain in result.stdout.decode().split(",") if domain.strip())

    home = Path.home()
    preference_dirs = [
        home / "Library/Preferences",
        *home.glob("Library/Containers/*/Data/Library/Preferences"),
        *home.glob("Library/Group Containers/*/Library/Preferences"),
    ]
    for directory in preference_dirs:
        if not directory.is_dir():
            continue
        for plist in directory.glob("*.plist"):
            if plist.stem != ".GlobalPreferences" and plist.stem not in CF_PSEUDO_DOMAINS:
                domains.add(plist.stem)
    return sorted(domains)


def current_shortcuts() -> dict[str, dict[str, str]]:
    captured: dict[str, dict[str, str]] = {}
    for domain in preference_domains():
        exported = export_domain(domain)
        if not exported:
            continue
        equivalents = exported.get(KEY)
        if not isinstance(equivalents, dict):
            continue
        shortcuts = {
            title: equivalent
            for title, equivalent in equivalents.items()
            if isinstance(title, str) and isinstance(equivalent, str)
        }
        if shortcuts:
            captured[domain] = dict(sorted(shortcuts.items()))
    return dict(sorted(captured.items()))


def validate_shortcuts(value: Any, source: Path) -> dict[str, dict[str, str]]:
    if not isinstance(value, dict):
        raise ValueError(f"{source}: root must be a dictionary")
    if value.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"{source}: schemaVersion must be {SCHEMA_VERSION}")
    shortcuts = value.get("shortcuts")
    if not isinstance(shortcuts, dict):
        raise ValueError(f"{source}: shortcuts must be a dictionary")

    validated: dict[str, dict[str, str]] = {}
    for domain, entries in shortcuts.items():
        if not isinstance(domain, str) or not domain:
            raise ValueError(f"{source}: domain names must be non-empty strings")
        if not isinstance(entries, dict):
            raise ValueError(f"{source}: {domain} must be a dictionary")
        validated_entries: dict[str, str] = {}
        for title, equivalent in entries.items():
            if not isinstance(title, str) or not isinstance(equivalent, str):
                raise ValueError(f"{source}: {domain} entries must be string pairs")
            validated_entries[title] = equivalent
        if validated_entries:
            validated[domain] = dict(sorted(validated_entries.items()))
    return dict(sorted(validated.items()))


def load_shortcuts(path: Path) -> dict[str, dict[str, str]]:
    try:
        with path.open("rb") as file:
            value = plistlib.load(file)
    except FileNotFoundError as error:
        raise ValueError(f"managed file not found: {path}") from error
    except plistlib.InvalidFileException as error:
        raise ValueError(f"invalid plist: {path}") from error
    return validate_shortcuts(value, path)


def write_shortcuts(path: Path, shortcuts: dict[str, dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"schemaVersion": SCHEMA_VERSION, "shortcuts": shortcuts}
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        plistlib.dump(payload, temporary, fmt=plistlib.FMT_XML, sort_keys=True)
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def print_diff(
    managed: dict[str, dict[str, str]], current: dict[str, dict[str, str]], summary: bool
) -> int:
    differences: list[str] = []
    for domain in sorted(set(managed) | set(current)):
        expected = managed.get(domain, {})
        actual = current.get(domain, {})
        for title in sorted(set(expected) | set(actual)):
            wanted = expected.get(title)
            found = actual.get(title)
            if wanted is None:
                differences.append(f"  [+current] {domain}: {title} = {found}")
            elif found is None:
                differences.append(f"  [-current] {domain}: {title} (expected {wanted})")
            elif wanted != found:
                differences.append(
                    f"  [changed] {domain}: {title} = {found} (expected {wanted})"
                )
    if not differences:
        if not summary:
            print("No diff: managed keyboard shortcuts match this Mac.")
        return 0
    if summary:
        print(f"Application shortcuts: {len(differences)} difference(s)")
        return 1
    print("Application shortcut differences:")
    print("\n".join(differences))
    return 1


def command_capture(output: Path) -> int:
    write_shortcuts(output, current_shortcuts())
    print(f"keyboard shortcuts saved to {output}")
    return 0


def command_cache() -> int:
    return command_capture(cache_path())


def command_sync() -> int:
    captured = current_shortcuts()
    write_shortcuts(managed_path(), captured)
    write_shortcuts(cache_path(), captured)
    print(f"keyboard shortcuts synced to {managed_path()}")
    return 0


def merge_shortcuts(
    managed: dict[str, dict[str, str]], current: dict[str, dict[str, str]]
) -> dict[str, dict[str, str]]:
    merged = {domain: dict(entries) for domain, entries in managed.items()}
    for domain, entries in current.items():
        merged.setdefault(domain, {}).update(entries)
    return {domain: dict(sorted(entries.items())) for domain, entries in sorted(merged.items())}


def command_merge() -> int:
    managed = load_shortcuts(managed_path())
    merged = merge_shortcuts(managed, current_shortcuts())
    write_shortcuts(managed_path(), merged)
    print(f"keyboard shortcuts merged into {managed_path()}")
    return 0


def command_diff(summary: bool) -> int:
    managed = load_shortcuts(managed_path())
    result = print_diff(managed, current_shortcuts(), summary)
    return 0 if summary else result


def command_apply() -> int:
    managed = load_shortcuts(managed_path())
    current = current_shortcuts()
    for domain in sorted(set(managed) | set(current)):
        entries = managed.get(domain, {})
        existing = current.get(domain, {})
        removed = sorted(set(existing) - set(entries))
        domain_flag = ["-globalDomain"] if domain == GLOBAL_DOMAIN else [domain]
        if entries:
            command = ["write", *domain_flag, KEY, "-dict"]
            for title, equivalent in entries.items():
                command.extend([title, equivalent])
            result = run_defaults(*command)
            if result.returncode != 0:
                print(f"Error: failed to update {domain}", file=sys.stderr)
                return result.returncode
            if removed:
                print(f"  REMOVED  {domain} ({len(removed)} shortcut(s)): {', '.join(removed)}")
            print(f"  APPLIED  {domain} ({len(entries)} shortcut(s))")
        elif removed:
            result = run_defaults("delete", *domain_flag, KEY)
            if result.returncode != 0:
                print(f"Error: failed to clear {domain}", file=sys.stderr)
                return result.returncode
            print(f"  REMOVED  {domain} ({len(removed)} shortcut(s)): {', '.join(removed)}")
    command_cache()
    print("Done. Quit and reopen affected applications to use the new shortcuts.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("apply")
    subparsers.add_parser("sync")
    subparsers.add_parser("merge")
    subparsers.add_parser("cache")
    diff_parser = subparsers.add_parser("diff")
    diff_parser.add_argument("--summary", action="store_true")
    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        if arguments.command == "apply":
            return command_apply()
        if arguments.command == "sync":
            return command_sync()
        if arguments.command == "merge":
            return command_merge()
        if arguments.command == "cache":
            return command_cache()
        if arguments.command == "diff":
            return command_diff(arguments.summary)
        return command_capture(arguments.output)
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
