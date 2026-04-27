#!/usr/bin/env python3
# scripts/setup_copilot_mcp.py
# Usage: python3 setup_copilot_mcp.py <command_or_url>
#   http://...   → HTTP/SSE mode (Copilot CLI requires this)
#   npx          → npx -y xmux-bridge (stdio, for other clients)
#   /path/to/js  → node <path> (stdio, for other clients)
import json, sys, os

SERVER_NAME = "xmux_bridge"
LEGACY_NAMES = {
    "xmux_bridge",
    "xmux-bridge",
    "clau_mux_bridge",
    "clau-mux-bridge",
    ("a" + "mux_bridge"),
    ("a" + "mux-bridge"),
}

cmd = sys.argv[1] if len(sys.argv) > 1 else "npx"
settings_path = os.path.expanduser("~/.copilot/mcp-config.json")

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

if "mcpServers" not in settings:
    settings["mcpServers"] = {}

for name in LEGACY_NAMES:
    settings["mcpServers"].pop(name, None)

TOOLS = ["write_to_lead"]

if cmd.startswith("http"):
    settings["mcpServers"][SERVER_NAME] = {
        "type": "sse",
        "url": cmd,
        "tools": TOOLS,
    }
elif cmd == "npx":
    settings["mcpServers"][SERVER_NAME] = {
        "command": "npx",
        "args": ["-y", "xmux-bridge"],
        "tools": TOOLS,
    }
else:
    settings["mcpServers"][SERVER_NAME] = {
        "command": "node",
        "args": [cmd],
        "tools": TOOLS,
    }

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
