import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_gemini_mcp.py"


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
        [sys.executable, str(SCRIPT), bridge],
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
