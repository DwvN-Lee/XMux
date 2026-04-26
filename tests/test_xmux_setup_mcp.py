import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_xmux_codex_mcp.py"


def _load_setup_module():
    spec = importlib.util.spec_from_file_location("setup_xmux_codex_mcp", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_remove_xmux_blocks_also_removes_legacy_prefix_blocks():
    setup = _load_setup_module()
    legacy = "a" + "mux"
    content = f"""
[marketplaces.{legacy}-local]
source_type = "local"
source = "/repo"

[plugins."{legacy}@{legacy}-local"]
enabled = true

[mcp_servers.{legacy}_lead]
command = "node"
args = ["/repo/{legacy}-lead-mcp-server.js"]

[mcp_servers.{legacy}_lead.env]
{"A" + "MUX_HOME"} = "/repo/.codex/{legacy}"

[marketplaces.xmux-local]
source_type = "local"
source = "/repo"

[plugins."xmux@xmux-local"]
enabled = true

[mcp_servers.xmux_lead]
command = "node"
args = ["/repo/xmux-lead-mcp-server.js"]

[mcp_servers.xmux_lead.env]
XMUX_HOME = "/repo/.codex/xmux"

[mcp_servers.other]
command = "true"
"""

    cleaned = setup.remove_xmux_blocks(content)

    assert legacy not in cleaned
    assert "xmux" not in cleaned
    assert "[mcp_servers.other]" in cleaned
