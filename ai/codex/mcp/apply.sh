#!/usr/bin/env bash
# servers.json にあって未登録の公式 MCP サーバーを Codex の共通設定へ追加する。

set -euo pipefail
umask 077

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SERVERS_FILE="${DOTFILES_DIR}/ai/codex/mcp/servers.json"

echo "==> Adding missing official MCP servers from servers.json..."
python3 - "${SERVERS_FILE}" <<'PYEOF'
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib
from datetime import datetime
from pathlib import Path

servers_path = sys.argv[1]

with open(servers_path, encoding="utf-8") as file:
    declared = json.load(file)

result = subprocess.run(
    ["codex", "mcp", "list", "--json"],
    capture_output=True,
    check=True,
    text=True,
)
actual = {entry["name"]: entry for entry in json.loads(result.stdout)}

changed = False
backup_dir = (
    Path.home()
    / ".dotfiles-backup"
    / datetime.now().strftime("%Y%m%d%H%M%S")
    / "codex-config"
)
backup_path = backup_dir / "config.toml"
backup_created = False


def toml_string(value):
    return json.dumps(value, ensure_ascii=False)


def transport_matches(entry, current):
    transport = current.get("transport", {})
    if entry["type"] == "stdio":
        return (
            transport.get("type") == "stdio"
            and transport.get("command") == entry["command"]
            and transport.get("args", []) == entry.get("args", [])
        )
    return transport.get("type") in {"http", "streamable_http"} and transport.get(
        "url"
    ) == entry["url"]


def backup_config():
    global backup_created

    config_path = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser() / "config.toml"
    if not config_path.exists() or backup_path.exists():
        return
    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_path, backup_path)
    backup_created = True


def update_http_auth(entry, headers):
    global backup_created

    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
    config_path = codex_home / "config.toml"
    with config_path.open("rb") as file:
        config = tomllib.load(file)

    server = config.get("mcp_servers", {}).get(entry["name"], {})
    current_headers = dict(server.get("http_headers", {}))
    wanted_headers = {**current_headers, **headers}
    if (
        server.get("url") == entry["url"]
        and not server.get("bearer_token_env_var")
        and current_headers == wanted_headers
    ):
        return False

    original = config_path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    table = f"[mcp_servers.{entry['name']}]"
    start = next(
        (index for index, line in enumerate(lines) if line.strip() == table),
        None,
    )
    if start is None:
        raise RuntimeError(f"MCP config table was not created: {entry['name']}")
    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if lines[index].lstrip().startswith("[")
        ),
        len(lines),
    )

    preserved = []
    for line in lines[start + 1 : end]:
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key not in {"bearer_token_env_var", "http_headers"}:
            preserved.append(line)

    header_items = ", ".join(
        f"{toml_string(key)} = {toml_string(value)}"
        for key, value in sorted(wanted_headers.items())
    )
    replacement = [lines[start], *preserved]
    if replacement and not replacement[-1].endswith("\n"):
        replacement[-1] += "\n"
    replacement.append(f"http_headers = {{ {header_items} }}\n")
    updated = "".join([*lines[:start], *replacement, *lines[end:]])

    backup_config()

    config_mode = stat.S_IMODE(config_path.stat().st_mode)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=config_path.parent, delete=False
    ) as temporary:
        temporary.write(updated)
        temporary_path = Path(temporary.name)
    os.chmod(temporary_path, config_mode)
    os.replace(temporary_path, config_path)
    return True


for entry in declared:
    name = entry["name"]
    current = actual.get(name)
    if current and transport_matches(entry, current):
        continue
    if current:
        backup_config()
        print(f"  replace  {name}")
        subprocess.run(
            ["codex", "mcp", "remove", name],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    else:
        print(f"  add  {name}")
    if entry["type"] == "stdio":
        command = [
            "codex",
            "mcp",
            "add",
            name,
            "--",
            entry["command"],
            *entry.get("args", []),
        ]
    else:
        command = ["codex", "mcp", "add", name, "--url", entry["url"]]

    add_result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if add_result.returncode != 0:
        # `codex mcp add --url` writes the config entry and then attempts an
        # OAuth handshake; the handshake commonly fails for servers that only
        # support bearer-token auth (added below), but the entry is still
        # written, so treat "entry now present" as success.
        recheck = subprocess.run(
            ["codex", "mcp", "list", "--json"], capture_output=True, check=True, text=True
        )
        if name not in {e["name"] for e in json.loads(recheck.stdout)}:
            raise RuntimeError(f"codex mcp add failed for {name}")
    changed = True

for entry in declared:
    if entry["type"] != "http":
        continue
    headers = {}
    for header_name, spec in entry.get("headers", {}).items():
        resolved = subprocess.run(
            spec["cmd"], capture_output=True, check=True, text=True
        ).stdout.strip()
        if not resolved:
            raise RuntimeError(f"Credential command returned an empty value: {header_name}")
        headers[header_name] = spec.get("prefix", "") + resolved
    if update_http_auth(entry, headers):
        print(f"  auth update  {entry['name']}")
        changed = True

if not changed:
    print("  (already up to date)")
elif backup_created:
    print(f"  backup  {backup_path}")
PYEOF
