import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_claude_mcp.py"


def _make_fake_homebrew_xmux_layout(tmp_path):
    prefix = tmp_path / "homebrew"
    cellar = prefix / "Cellar" / "xmux" / "1.0.35" / "libexec"
    opt = prefix / "opt" / "xmux" / "libexec"
    for root in (cellar, opt):
        root.mkdir(parents=True)
        (root / "xmux.zsh").write_text("# xmux\n", encoding="utf-8")
        (root / "bridge-mcp-server.js").write_text("#!/usr/bin/env node\n", encoding="utf-8")
    return cellar, opt


def test_setup_claude_mcp_replaces_project_local_legacy_bridge_names(tmp_path):
    home = tmp_path / "home"
    project = tmp_path / "project"
    state_dir = project / ".codex" / "xmux"
    outbox = state_dir / "teams" / "demo" / "inboxes" / "codex-lead.json"
    install_dir = tmp_path / "install"
    bridge = install_dir / "bridge-mcp-server.js"
    home.mkdir()
    project.mkdir()
    install_dir.mkdir()

    config_path = home / ".claude.json"
    config_path.write_text(
        json.dumps(
            {
                "numStartups": 3,
                "projects": {
                    str(project): {
                        "allowedTools": ["Read"],
                        "mcpServers": {
                            "clau_mux_bridge": {
                                "command": "node",
                                "args": ["/old/bridge-mcp-server.js"],
                            },
                            "xmux-bridge": {"command": "npx", "args": ["-y", "old"]},
                            "chrome-devtools": {"command": "npx", "args": ["chrome"]},
                        },
                    },
                    "/other/project": {
                        "mcpServers": {
                            "xmux_bridge": {"command": "node", "args": ["/other/server.js"]}
                        }
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["HOME"] = str(home)
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            str(bridge),
            str(project),
            str(outbox),
            "claude-worker",
            "demo",
            str(state_dir),
            str(install_dir),
        ],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    settings = json.loads(config_path.read_text(encoding="utf-8"))
    assert settings["numStartups"] == 3
    project_cfg = settings["projects"][str(project)]
    servers = project_cfg["mcpServers"]
    assert project_cfg["allowedTools"] == ["Read"]
    assert "clau_mux_bridge" not in servers
    assert "xmux-bridge" not in servers
    assert servers["chrome-devtools"] == {"command": "npx", "args": ["chrome"]}
    assert servers["xmux_bridge"] == {
        "type": "stdio",
        "command": "node",
        "args": [
            str(bridge),
            "--outbox",
            str(outbox),
            "--agent",
            "claude-worker",
            "--team",
            "demo",
        ],
        "env": {
            "XMUX_AGENT": "claude-worker",
            "XMUX_INSTALL_DIR": str(install_dir),
            "XMUX_OUTBOX": str(outbox),
            "XMUX_PROJECT_DIR": str(project),
            "XMUX_STATE_DIR": str(state_dir),
            "XMUX_TEAM": "demo",
        },
    }
    assert settings["projects"]["/other/project"]["mcpServers"]["xmux_bridge"] == {
        "command": "node",
        "args": ["/other/server.js"],
    }


def test_setup_claude_mcp_targets_homebrew_opt_path(tmp_path):
    home = tmp_path / "home"
    project = tmp_path / "project"
    state_dir = project / ".codex" / "xmux"
    outbox = state_dir / "teams" / "demo" / "inboxes" / "codex-lead.json"
    cellar, opt = _make_fake_homebrew_xmux_layout(tmp_path)
    home.mkdir()
    project.mkdir()

    env = os.environ.copy()
    env["HOME"] = str(home)
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            str(cellar / "bridge-mcp-server.js"),
            str(project),
            str(outbox),
            "claude-worker",
            "demo",
            str(state_dir),
            str(cellar),
        ],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    settings = json.loads((home / ".claude.json").read_text(encoding="utf-8"))
    server = settings["projects"][str(project)]["mcpServers"]["xmux_bridge"]
    assert server["args"][0] == str(opt / "bridge-mcp-server.js")
    assert server["env"]["XMUX_INSTALL_DIR"] == str(opt)
    assert str(cellar) not in json.dumps(server)
