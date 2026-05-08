#!/usr/bin/env python3
"""Configure Claude Code local MCP for XMux teammate callbacks.

Usage:
  python3 setup_claude_mcp.py <bridge_js> <project_dir> <outbox> <agent> <team> <state_dir> <install_dir>
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

SERVER_NAME = "xmux_bridge"
LEGACY_NAMES = {
    "xmux_bridge",
    "xmux-bridge",
    "clau_mux_bridge",
    "clau-mux-bridge",
    ("a" + "mux_bridge"),
    ("a" + "mux-bridge"),
}


def _absolute(path: str) -> str:
    return os.path.abspath(os.path.expanduser(path))


def _stable_homebrew_xmux_install_dir(install_dir: str) -> str:
    resolved = _absolute(install_dir)
    marker = f"{os.sep}Cellar{os.sep}xmux{os.sep}"
    if marker not in resolved or not resolved.endswith(f"{os.sep}libexec"):
        return resolved

    prefix = resolved.split(marker, 1)[0]
    candidate = os.path.join(prefix, "opt", "xmux", "libexec")
    if os.path.isfile(os.path.join(candidate, "xmux.zsh")):
        return candidate
    return resolved


def _stable_homebrew_xmux_file_path(path: str) -> str:
    resolved = _absolute(path)
    install_dir = os.path.dirname(resolved)
    stable_install_dir = _stable_homebrew_xmux_install_dir(install_dir)
    if stable_install_dir == install_dir:
        return resolved

    candidate = os.path.join(stable_install_dir, os.path.basename(resolved))
    if os.path.isfile(candidate):
        return candidate
    return resolved


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"error: {path} must contain a JSON object")
    return data


def _atomic_write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
        text=True,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, sort_keys=True, ensure_ascii=True)
            fh.write("\n")
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def _usage() -> None:
    print(
        "usage: setup_claude_mcp.py <bridge_js> <project_dir> <outbox> "
        "<agent> <team> <state_dir> <install_dir>",
        file=sys.stderr,
    )


def main() -> int:
    if len(sys.argv) != 8:
        _usage()
        return 2

    bridge_js = _stable_homebrew_xmux_file_path(sys.argv[1])
    project_dir = _absolute(sys.argv[2])
    outbox = _absolute(sys.argv[3])
    agent = sys.argv[4]
    team = sys.argv[5]
    state_dir = _absolute(sys.argv[6])
    install_dir = _stable_homebrew_xmux_install_dir(sys.argv[7])

    config_path = Path(os.path.expanduser("~/.claude.json"))
    config = _load_json(config_path)

    projects = config.setdefault("projects", {})
    if not isinstance(projects, dict):
        raise SystemExit("error: ~/.claude.json projects must be a JSON object")

    project = projects.setdefault(project_dir, {})
    if not isinstance(project, dict):
        raise SystemExit(f"error: Claude project entry for {project_dir} must be a JSON object")

    servers = project.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        raise SystemExit(f"error: Claude mcpServers for {project_dir} must be a JSON object")

    for name in LEGACY_NAMES:
        servers.pop(name, None)

    servers[SERVER_NAME] = {
        "type": "stdio",
        "command": "node",
        "args": [
            bridge_js,
            "--outbox",
            outbox,
            "--agent",
            agent,
            "--team",
            team,
        ],
        "env": {
            "XMUX_AGENT": agent,
            "XMUX_INSTALL_DIR": install_dir,
            "XMUX_OUTBOX": outbox,
            "XMUX_PROJECT_DIR": project_dir,
            "XMUX_STATE_DIR": state_dir,
            "XMUX_TEAM": team,
        },
    }

    _atomic_write_json(config_path, config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
