#!/usr/bin/env python3
"""Finder sidebar management — mysides drop-in replacement via pyobjc.

Usage:
  uv run --with pyobjc python3 macos/mysides.py list
  uv run --with pyobjc python3 macos/mysides.py add <name> <file-url>
  uv run --with pyobjc python3 macos/mysides.py remove <name>
"""
import sys
import CoreServices as CS
from Foundation import NSURL


def _list_ref():
    ref = CS.LSSharedFileListCreate(None, CS.kLSSharedFileListFavoriteItems, None)
    if ref is None:
        print("Error: LSSharedFileListCreate failed — sidebar API unavailable", file=sys.stderr)
        sys.exit(1)
    return ref


def _items(list_ref):
    result = CS.LSSharedFileListCopySnapshot(list_ref, None)
    return result[0] if result else []


def cmd_list():
    ref = _list_ref()
    for item in _items(ref):
        name = CS.LSSharedFileListItemCopyDisplayName(item)
        url_result = CS.LSSharedFileListItemCopyResolvedURL(item, 0, None)
        url = url_result[0] if url_result and url_result[0] else None
        # Items without a resolvable URL (e.g. network locations) are skipped.
        if url:
            print(f"{name} -> {url}")


def cmd_add(name, url_str):
    ref = _list_ref()
    url = NSURL.URLWithString_(url_str)
    if url is None:
        print(f"Error: invalid URL: {url_str!r}", file=sys.stderr)
        sys.exit(1)
    result = CS.LSSharedFileListInsertItemURL(
        ref, CS.kLSSharedFileListItemLast, name, None, url, {}, []
    )
    if result is None:
        print(f"Error: failed to insert sidebar item: {name!r}", file=sys.stderr)
        sys.exit(1)


def cmd_remove(name):
    ref = _list_ref()
    for item in _items(ref):
        if CS.LSSharedFileListItemCopyDisplayName(item) == name:
            CS.LSSharedFileListItemRemove(ref, item)
            return
    print(f"Warning: sidebar item not found: {name!r}", file=sys.stderr)
    sys.exit(1)


COMMANDS = {
    "list": (cmd_list, 0),
    "add": (cmd_add, 2),
    "remove": (cmd_remove, 1),
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(f"Usage: {sys.argv[0]} list|add <name> <url>|remove <name>", file=sys.stderr)
        sys.exit(1)
    cmd, nargs = COMMANDS[sys.argv[1]]
    args = sys.argv[2:]
    if len(args) != nargs:
        print(f"Wrong number of arguments for '{sys.argv[1]}'", file=sys.stderr)
        sys.exit(1)
    cmd(*args)
