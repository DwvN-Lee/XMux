import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_copilot_mcp.js"


def _make_fake_homebrew_xmux_layout(tmp_path):
    prefix = tmp_path / "homebrew"
    cellar = prefix / "Cellar" / "xmux" / "1.0.35" / "libexec"
    opt = prefix / "opt" / "xmux" / "libexec"
    for root in (cellar, opt):
        root.mkdir(parents=True)
        (root / "xmux.zsh").write_text("# xmux\n", encoding="utf-8")
        (root / "bridge-mcp-server.js").write_text("#!/usr/bin/env node\n", encoding="utf-8")
    return cellar, opt


def test_setup_copilot_mcp_replaces_legacy_bridge_names(tmp_path):
    home = tmp_path / "home"
    settings_path = home / ".copilot" / "mcp-config.json"
    settings_path.parent.mkdir(parents=True)
    settings_path.write_text(
        json.dumps(
            {
                "mcpServers": {
                    "clau_mux_bridge": {
                        "type": "sse",
                        "url": "http://127.0.0.1:1/sse",
                    },
                    "xmux-bridge": {"command": "npx", "args": ["-y", "old"]},
                    "chrome-devtools": {"command": "npx", "args": ["chrome"]},
                }
            }
        ),
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["HOME"] = str(home)
    url = "http://127.0.0.1:58452/sse"
    result = subprocess.run(
        ["node", str(SCRIPT), url],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    servers = settings["mcpServers"]
    assert "clau_mux_bridge" not in servers
    assert "xmux-bridge" not in servers
    assert servers["chrome-devtools"] == {"command": "npx", "args": ["chrome"]}
    assert servers["xmux_bridge"] == {
        "type": "sse",
        "url": url,
        "tools": ["write_to_lead"],
    }


def test_setup_copilot_mcp_targets_homebrew_opt_path_for_stdio(tmp_path):
    home = tmp_path / "home"
    settings_path = home / ".copilot" / "mcp-config.json"
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
