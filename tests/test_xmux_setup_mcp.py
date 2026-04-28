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
    assert "XMUX_PROJECT_DIR" not in block
    assert "XMUX_STATE_DIR" not in block


def test_install_local_plugin_cache_writes_install_marker(tmp_path):
    setup = _load_setup_module()
    config_path = tmp_path / ".codex" / "config.toml"

    setup.install_local_plugin_cache(str(config_path), str(ROOT))

    cache_path = (
        tmp_path
        / ".codex"
        / "plugins"
        / "cache"
        / "xmux-local"
        / "xmux"
        / "local"
    )
    assert (cache_path / "bin" / "xmux").is_file()
    assert (cache_path / ".xmux-install-dir").read_text(encoding="utf-8").strip() == str(ROOT)


def test_ensure_codex_shell_environment_adds_xmux_wrapper_path(monkeypatch):
    setup = _load_setup_module()
    monkeypatch.setattr(setup, "resolve_path_with_node", lambda: "/node/bin:/usr/bin")

    content = """
[shell_environment_policy.set]
TMPDIR = "/tmp/codex"
"""

    updated = setup.ensure_codex_shell_environment(content, "/repo/XMux")

    assert 'PATH = "/repo/XMux/bin:/node/bin:/usr/bin"' in updated
    assert 'XMUX_INSTALL_DIR = "/repo/XMux"' in updated
    assert 'TMPDIR = "/tmp/codex"' in updated


def test_ensure_codex_shell_environment_deduplicates_xmux_wrapper_path():
    setup = _load_setup_module()
    content = """
[shell_environment_policy.set]
PATH = "/usr/bin:/repo/XMux/bin:/bin"
XMUX_INSTALL_DIR = "/old"
"""

    updated = setup.ensure_codex_shell_environment(content, "/repo/XMux")

    assert 'PATH = "/repo/XMux/bin:/usr/bin:/bin"' in updated
    assert 'XMUX_INSTALL_DIR = "/repo/XMux"' in updated


def test_install_xmux_command_rule_is_marker_scoped(tmp_path):
    setup = _load_setup_module()
    config_path = tmp_path / ".codex" / "config.toml"
    rules_path = tmp_path / ".codex" / "rules" / "default.rules"
    rules_path.parent.mkdir(parents=True)
    rules_path.write_text('prefix_rule(pattern=["pwd"], decision="allow")\n', encoding="utf-8")

    setup.install_xmux_command_rule(str(config_path))
    setup.install_xmux_command_rule(str(config_path))

    rules = rules_path.read_text(encoding="utf-8")
    assert rules.count('prefix_rule(pattern=["xmux"], decision="allow")') == 1
    assert 'prefix_rule(pattern=["pwd"], decision="allow")' in rules

    setup.remove_xmux_command_rule(str(config_path))

    rules = rules_path.read_text(encoding="utf-8")
    assert 'prefix_rule(pattern=["xmux"], decision="allow")' not in rules
    assert 'prefix_rule(pattern=["pwd"], decision="allow")' in rules
