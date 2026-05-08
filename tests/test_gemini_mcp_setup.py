import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_gemini_mcp.js"


def _make_fake_homebrew_xmux_layout(tmp_path):
    prefix = tmp_path / "homebrew"
    cellar = prefix / "Cellar" / "xmux" / "1.0.35" / "libexec"
    opt = prefix / "opt" / "xmux" / "libexec"
    for root in (cellar, opt):
        root.mkdir(parents=True)
        (root / "xmux.zsh").write_text("# xmux\n", encoding="utf-8")
        (root / "bridge-mcp-server.js").write_text("#!/usr/bin/env node\n", encoding="utf-8")
    return cellar, opt


def test_setup_gemini_mcp_replaces_legacy_bridge_names(tmp_path):
    home = tmp_path / "home"
    settings_path = home / ".gemini" / "settings.json"
    settings_path.parent.mkdir(parents=True)
    settings_path.write_text(
        json.dumps(
            {
                "model": {"name": "pro"},
                "mcpServers": {
                    "clau_mux_bridge": {
                        "command": "node",
                        "args": ["/old/bridge-mcp-server.js"],
                    },
                    "xmux-bridge": {"command": "npx", "args": ["-y", "old"]},
                    "other": {"command": "true"},
                }
            }
        ),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["HOME"] = str(home)
    bridge = "/repo/bridge-mcp-server.js"
    result = subprocess.run(
        ["node", str(SCRIPT), bridge],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    servers = settings["mcpServers"]
    assert settings["model"] == {"name": "pro"}
    assert "clau_mux_bridge" not in servers
    assert "xmux-bridge" not in servers
    assert servers["other"] == {"command": "true"}
    assert servers["xmux_bridge"] == {
        "command": "node",
        "args": [bridge],
        "trust": True,
    }


def test_setup_gemini_mcp_targets_homebrew_opt_path(tmp_path):
    home = tmp_path / "home"
    settings_path = home / ".gemini" / "settings.json"
    cellar, opt = _make_fake_homebrew_xmux_layout(tmp_path)

    env = os.environ.copy()
    env["HOME"] = str(home)
    result = subprocess.run(
        ["node", str(SCRIPT), str(cellar / "bridge-mcp-server.js")],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    assert settings["mcpServers"]["xmux_bridge"]["args"] == [
        str(opt / "bridge-mcp-server.js")
    ]
