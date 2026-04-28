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


def _run_main(setup, monkeypatch, args):
    monkeypatch.setattr(setup.sys, "argv", ["setup_xmux_codex_mcp.py", *args])
    try:
        setup.main()
    except SystemExit as exc:
        return int(exc.code or 0)
    return 0


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


def test_explicit_setup_writes_config_rules_without_implicit_skill_source(
    tmp_path, monkeypatch, capsys
):
    setup = _load_setup_module()
    monkeypatch.setattr(setup, "resolve_path_with_node", lambda: "/node/bin:/usr/bin")
    codex_home = tmp_path / "codex-home"
    server_path = ROOT / "xmux-lead-mcp-server.js"

    rc = _run_main(
        setup,
        monkeypatch,
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(ROOT),
            "--server-path",
            str(server_path),
        ],
    )
    output = capsys.readouterr().out

    assert rc == 0
    config = (codex_home / "config.toml").read_text(encoding="utf-8")
    assert "[mcp_servers.xmux_lead]" in config
    assert f'args = ["{server_path}"]' in config
    assert f'PATH = "{ROOT}/bin:/node/bin:/usr/bin"' in config
    assert f'XMUX_INSTALL_DIR = "{ROOT}"' in config
    assert "XMUX_PROJECT_DIR =" not in config
    assert "XMUX_STATE_DIR =" not in config
    assert "[marketplaces.xmux-local]" not in config
    assert '[plugins."xmux@xmux-local"]' not in config

    rules = (codex_home / "rules" / "default.rules").read_text(encoding="utf-8")
    assert 'prefix_rule(pattern=["xmux"], decision="allow")' in rules
    assert not (codex_home / "skills").exists()
    assert not (codex_home / "plugins" / "cache" / "xmux-local").exists()
    assert setup.doctor_codex(str(codex_home / "config.toml"), str(ROOT), str(server_path)) == 0
    doctor_output = capsys.readouterr().out
    assert "skills: skipped; pass --skills-dir or set XMUX_CODEX_SKILLS_DIR" in output
    assert "no XMux skill source directory found" in doctor_output


def test_explicit_setup_removes_legacy_plugin_cache(tmp_path, monkeypatch, capsys):
    setup = _load_setup_module()
    monkeypatch.setattr(setup, "resolve_path_with_node", lambda: "/node/bin:/usr/bin")
    codex_home = tmp_path / "codex-home"
    stale_cache = codex_home / "plugins" / "cache" / "xmux-local" / "xmux" / "local"
    stale_cache.mkdir(parents=True)
    (stale_cache / ".codex-plugin").mkdir()
    (stale_cache / ".codex-plugin" / "plugin.json").write_text("{}", encoding="utf-8")

    rc = _run_main(
        setup,
        monkeypatch,
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(ROOT),
            "--server-path",
            str(ROOT / "xmux-lead-mcp-server.js"),
        ],
    )
    output = capsys.readouterr().out

    assert rc == 0
    config = (codex_home / "config.toml").read_text(encoding="utf-8")
    assert "[marketplaces.xmux-local]" not in config
    assert '[plugins."xmux@xmux-local"]' not in config
    assert not (codex_home / "plugins" / "cache" / "xmux-local").exists()
    assert "plugin_cache: disabled" in output


def test_explicit_setup_accepts_external_skills_dir_for_runtime_only_install(
    tmp_path, monkeypatch, capsys
):
    setup = _load_setup_module()
    monkeypatch.setattr(setup, "resolve_path_with_node", lambda: "/node/bin:/usr/bin")
    codex_home = tmp_path / "codex-home"
    install_dir = tmp_path / "runtime-install"
    install_dir.mkdir()
    skills_dir = tmp_path / "external-skills"
    skill = skills_dir / "xmux-external"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("name: xmux-external\n", encoding="utf-8")
    server_path = install_dir / "xmux-lead-mcp-server.js"

    rc = _run_main(
        setup,
        monkeypatch,
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(install_dir),
            "--server-path",
            str(server_path),
            "--skills-dir",
            str(skills_dir),
        ],
    )
    capsys.readouterr()

    assert rc == 0
    installed = codex_home / "skills" / "xmux-external"
    assert (installed / "SKILL.md").is_file()
    assert (installed / setup.SKILL_MARKER).read_text(encoding="utf-8").strip() == str(skill)
    assert not (codex_home / "plugins").exists()
    assert (
        setup.doctor_codex(
            str(codex_home / "config.toml"),
            str(install_dir),
            str(server_path),
            skills_dir=str(skills_dir),
        )
        == 0
    )
    capsys.readouterr()


def test_remove_deletes_xmux_codex_assets_but_keeps_other_state(tmp_path, monkeypatch, capsys):
    setup = _load_setup_module()
    monkeypatch.setattr(setup, "resolve_path_with_node", lambda: "/node/bin:/usr/bin")
    codex_home = tmp_path / "codex-home"
    config_path = codex_home / "config.toml"
    config_path.parent.mkdir(parents=True)
    config_path.write_text(
        """
[mcp_servers.other]
command = "true"

[shell_environment_policy.set]
TMPDIR = "/tmp/codex"
PATH = "/custom/bin"
""".lstrip(),
        encoding="utf-8",
    )

    setup_args = [
        "--home",
        str(codex_home),
        "--xmux-install-dir",
        str(ROOT),
        "--server-path",
        str(ROOT / "xmux-lead-mcp-server.js"),
        "--skills-dir",
        str(ROOT / "skills"),
    ]
    assert _run_main(setup, monkeypatch, setup_args) == 0
    capsys.readouterr()
    other_skill = codex_home / "skills" / "other-skill"
    other_skill.mkdir()
    (other_skill / "SKILL.md").write_text("other\n", encoding="utf-8")
    user_xmux_skill = codex_home / "skills" / "xmux-user-skill"
    user_xmux_skill.mkdir()
    (user_xmux_skill / "SKILL.md").write_text("user owned\n", encoding="utf-8")

    assert _run_main(setup, monkeypatch, ["--remove", "--home", str(codex_home), "--xmux-install-dir", str(ROOT)]) == 0
    capsys.readouterr()

    config = config_path.read_text(encoding="utf-8")
    assert "[mcp_servers.xmux_lead]" not in config
    assert "[marketplaces.xmux-local]" not in config
    assert '[plugins."xmux@xmux-local"]' not in config
    assert f"{ROOT}/bin" not in config
    assert f'XMUX_INSTALL_DIR = "{ROOT}"' not in config
    assert "[mcp_servers.other]" in config
    assert 'TMPDIR = "/tmp/codex"' in config
    assert 'PATH = "/custom/bin"' in config
    assert not (codex_home / "skills" / "xmux-teams").exists()
    assert (other_skill / "SKILL.md").is_file()
    assert (user_xmux_skill / "SKILL.md").is_file()
    assert not (codex_home / "plugins" / "cache" / "xmux-local").exists()


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
