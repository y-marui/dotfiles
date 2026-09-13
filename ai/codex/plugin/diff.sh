#!/usr/bin/env bash
# Codex app-server が返す local / remote plugin 実態を管理する。

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PLUGINS_FILE="${DOTFILES_DIR}/ai/codex/plugin/plugins.json"
ACTION="diff"
SUMMARY_MODE=0
case "${1:-}" in
  "") ;;
  --summary) SUMMARY_MODE=1 ;;
  apply|prune) ACTION="$1" ;;
  *)
    echo "usage: $0 [--summary|apply|prune]" >&2
    exit 2
    ;;
esac
[[ "$#" -le 1 ]] || {
  echo "usage: $0 [--summary|apply|prune]" >&2
  exit 2
}

python3 - "${PLUGINS_FILE}" "${ACTION}" "${SUMMARY_MODE}" <<'PYEOF'
import json
import subprocess
import sys

plugins_path, action = sys.argv[1:3]
summary = sys.argv[3] == "1"


class AppServer:
    def __init__(self):
        self.process = subprocess.Popen(
            ["codex", "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if self.process.stdin is None or self.process.stdout is None:
            raise RuntimeError("codex app-server の標準入出力を開けませんでした")
        self.next_id = 0
        self.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "dots_plugin_manager",
                    "title": "dots plugin manager",
                    "version": "1.0.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        )
        self.notify("initialized", {})

    def _send(self, message):
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def _read(self):
        assert self.process.stdout is not None
        line = self.process.stdout.readline()
        if line:
            return json.loads(line)
        stderr = ""
        if self.process.stderr is not None:
            stderr = self.process.stderr.read().strip()
        detail = f": {stderr}" if stderr else ""
        raise RuntimeError(f"codex app-server が応答せず終了しました{detail}")

    def request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self._send({"method": method, "id": request_id, "params": params})
        while True:
            message = self._read()
            if message.get("id") == request_id:
                if "error" in message:
                    raise RuntimeError(
                        f"codex app-server {method} failed: {message['error']}"
                    )
                return message["result"]
            if "id" in message and "method" in message:
                raise RuntimeError(
                    f"codex app-server {method} requires interactive handling: "
                    f"{message['method']}"
                )

    def notify(self, method, params):
        self._send({"method": method, "params": params})

    def close(self):
        if self.process.poll() is not None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


def load_plugins(server):
    result = server.request("plugin/list", {"forceRefetch": False})
    errors = result.get("marketplaceLoadErrors", [])
    if errors:
        details = "; ".join(error.get("message", str(error)) for error in errors)
        raise RuntimeError(f"plugin marketplace の読み込みに失敗しました: {details}")

    plugins = {}
    for marketplace in result.get("marketplaces", []):
        for plugin in marketplace.get("plugins", []):
            plugin_id = plugin["id"]
            plugins[plugin_id] = (marketplace, plugin)
    return plugins


def install_plugin(server, plugin_id, marketplace, plugin):
    if plugin.get("source", {}).get("type") == "remote":
        server.request(
            "plugin/install",
            {
                "pluginName": plugin["name"],
                "remoteMarketplaceName": marketplace["name"],
            },
        )
        return
    subprocess.run(["codex", "plugin", "add", plugin_id], check=True)


def uninstall_plugin(server, plugin_id, plugin):
    if plugin.get("source", {}).get("type") == "remote":
        server.request("plugin/uninstall", {"pluginId": plugin_id})
        return
    subprocess.run(["codex", "plugin", "remove", plugin_id], check=True)

with open(plugins_path, encoding="utf-8") as file:
    declared = set(json.load(file).get("plugins", []))

server = AppServer()
try:
    available = load_plugins(server)
    actual = {
        plugin_id
        for plugin_id, (_, plugin) in available.items()
        if plugin.get("installed", False)
    }
    only_actual = sorted(actual - declared)
    only_files = sorted(declared - actual)

    if action == "apply":
        if not only_files:
            print("  (already up to date)")
            raise SystemExit(0)
        for plugin_id in only_files:
            entry = available.get(plugin_id)
            if entry is None:
                raise RuntimeError(
                    f"plugin {plugin_id!r} は利用可能な marketplace にありません"
                )
            print(f"  install  {plugin_id}", flush=True)
            install_plugin(server, plugin_id, *entry)
        raise SystemExit(0)

    if action == "prune":
        if not only_actual:
            print("  (nothing to prune)")
            raise SystemExit(0)
        for plugin_id in only_actual:
            _, plugin = available[plugin_id]
            print(f"  remove  {plugin_id}", flush=True)
            uninstall_plugin(server, plugin_id, plugin)
        raise SystemExit(0)

    if summary:
        parts = []
        if only_actual:
            parts.append(f"+{len(only_actual)} actual のみ")
        if only_files:
            parts.append(f"-{len(only_files)} files のみ")
        if parts:
            print(" / ".join(parts))
        raise SystemExit(1 if parts else 0)

    if not only_actual and not only_files:
        print(
            "No diff: 実際の plugin インストール状態と plugins.json は一致しています。"
        )
        raise SystemExit(0)

    if only_actual:
        print(
            "インストール済みだが plugins.json 未記載 "
            "(+actual のみ。local/remote source を含む):"
        )
        for name in only_actual:
            print(f"  [+actual]  {name}")
        print()
    if only_files:
        print("plugins.json にあるが未インストール (-files のみ):")
        for name in only_files:
            print(f"  [-files]   {name}")

    raise SystemExit(1)
finally:
    server.close()
PYEOF
