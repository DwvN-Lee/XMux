#!/usr/bin/env python3
# scripts/setup_gemini_mcp.py
# Usage: python3 setup_gemini_mcp.py <command>
# <command>: "npx" (default) or absolute path to bridge-mcp-server.js
import json
import os
import sys

SERVER_NAME = "xmux_bridge"
LEGACY_NAMES = {
    "xmux_bridge",
    "xmux-bridge",
    "clau_mux_bridge",
    "clau-mux-bridge",
    ("a" + "mux_bridge"),
    ("a" + "mux-bridge"),
}
NPM_PIN = "xmux-bridge@^1.3.0"


def _stable_homebrew_xmux_file_path(path):
    resolved = os.path.abspath(os.path.expanduser(path))
    install_dir = os.path.dirname(resolved)
    marker = f"{os.sep}Cellar{os.sep}xmux{os.sep}"
    if marker not in install_dir or not install_dir.endswith(f"{os.sep}libexec"):
        return resolved

    prefix = install_dir.split(marker, 1)[0]
    opt_dir = os.path.join(prefix, "opt", "xmux", "libexec")
    candidate = os.path.join(opt_dir, os.path.basename(resolved))
    if os.path.isfile(os.path.join(opt_dir, "xmux.zsh")) and os.path.isfile(candidate):
        return candidate
    return resolved


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "npx"
    settings_path = os.path.expanduser("~/.gemini/settings.json")

    if os.path.exists(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)
    else:
        settings = {}

    servers = settings.setdefault("mcpServers", {})
    for name in LEGACY_NAMES:
        servers.pop(name, None)

    if cmd == "npx":
        servers[SERVER_NAME] = {
            "command": "npx",
            "args": ["-y", NPM_PIN],
            "trust": True,
        }
    else:
        servers[SERVER_NAME] = {
            "command": "node",
            "args": [_stable_homebrew_xmux_file_path(cmd)],
            "trust": True,
        }

    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)


if __name__ == "__main__":
    main()
