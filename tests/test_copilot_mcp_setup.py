import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_copilot_mcp.py"


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
        [sys.executable, str(SCRIPT), url],
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
