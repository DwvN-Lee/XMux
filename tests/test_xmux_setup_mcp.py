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
XMUX_STATE_DIR = "/repo/.codex/xmux"

[mcp_servers.other]
command = "true"
"""

    cleaned = setup.remove_xmux_blocks(content)

    assert legacy not in cleaned
    assert "xmux" not in cleaned
    assert "[mcp_servers.other]" in cleaned


def test_build_block_writes_new_env_names(monkeypatch):
    setup = _load_setup_module()
    monkeypatch.setattr(setup, "resolve_path_with_node", lambda: "/node/bin:/usr/bin")

    block = setup.build_block(
        "/repo/xmux-lead-mcp-server.js",
        "/repo/XMux",
        "/work/project",
        "/work/project/.codex/xmux",
    )

    assert 'XMUX_INSTALL_DIR = "/repo/XMux"' in block
    assert 'XMUX_PROJECT_DIR = "/work/project"' in block
    assert 'XMUX_STATE_DIR = "/work/project/.codex/xmux"' in block
