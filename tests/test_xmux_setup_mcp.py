import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "setup_xmux_codex_mcp.js"


def _node_call(function_name, *args, cwd=None, env=None):
    node_driver = """
const mod = require(process.argv[1]);
const fnName = process.argv[2];
const fnArgs = JSON.parse(process.argv[3]);
const fn = mod[fnName];
if (typeof fn !== 'function') {
  console.error(`missing function: ${fnName}`);
  process.exit(3);
}
function toJsonSafe(value) {
  if (value instanceof Set) return Array.from(value);
  if (Array.isArray(value)) return value.map(toJsonSafe);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = toJsonSafe(v);
    return out;
  }
  return value;
}
(async () => {
  const value = await fn(...fnArgs);
  process.stdout.write(JSON.stringify(toJsonSafe(value)));
})().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(2);
});
""".strip()
    result = subprocess.run(
        ["node", "-e", node_driver, str(SCRIPT), function_name, json.dumps(args)],
        capture_output=True,
        text=True,
        timeout=10,
        cwd=cwd,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout) if result.stdout else None


def _run_cli(args, cwd=None, env=None):
    return subprocess.run(
        ["node", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        timeout=20,
        cwd=cwd,
        env=env,
    )


def _make_fake_homebrew_xmux_layout(tmp_path):
    prefix = tmp_path / "homebrew"
    cellar = prefix / "Cellar" / "xmux" / "1.0.35" / "libexec"
    opt = prefix / "opt" / "xmux" / "libexec"
    for root in (cellar, opt):
        (root / "bin").mkdir(parents=True)
        (root / "xmux.zsh").write_text("# xmux\n", encoding="utf-8")
        (root / "bin" / "xmux").write_text("#!/bin/sh\n", encoding="utf-8")
        (root / "xmux-lead-mcp-server.js").write_text("#!/usr/bin/env node\n", encoding="utf-8")
        (root / "bridge-mcp-server.js").write_text("#!/usr/bin/env node\n", encoding="utf-8")
    return cellar, opt


def test_remove_xmux_blocks_also_removes_legacy_prefix_blocks():
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

    cleaned = _node_call("remove_xmux_blocks", content)

    assert legacy not in cleaned
    assert "xmux" not in cleaned
    assert "[mcp_servers.other]" in cleaned


def test_build_block_writes_new_env_names():
    block = _node_call(
        "build_block",
        "/repo/xmux-lead-mcp-server.js",
        "/repo/XMux",
        "/work/project",
        "/work/project/.codex/xmux",
    )

    assert 'XMUX_INSTALL_DIR = "/repo/XMux"' in block
    assert "XMUX_PROJECT_DIR" not in block
    assert "XMUX_STATE_DIR" not in block


def test_default_setup_writes_npx_mcp_with_homebrew_install_dir(tmp_path):
    codex_home = tmp_path / "codex-home"
    install_dir = tmp_path / "runtime-install"
    install_dir.mkdir()
    (install_dir / "package.json").write_text(
        json.dumps({"name": "xmux-test-runtime", "version": "9.8.7"}),
        encoding="utf-8",
    )

    result = _run_cli(
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(install_dir),
        ]
    )

    assert result.returncode == 0, result.stderr
    config = (codex_home / "config.toml").read_text(encoding="utf-8")
    assert 'command = "npx"' in config
    assert 'args = ["-y", "-p", "xmux-test-runtime@9.8.7", "xmux-lead-mcp"]' in config
    assert f'XMUX_INSTALL_DIR = "{install_dir}"' in config
    assert "XMUX_PROJECT_DIR =" not in config
    assert "XMUX_STATE_DIR =" not in config
    assert "mcp: npx -y -p xmux-test-runtime@9.8.7 xmux-lead-mcp" in result.stdout

    doctor = _run_cli(
        [
            "--doctor",
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(install_dir),
        ]
    )
    assert doctor.returncode == 0, doctor.stdout + doctor.stderr


def test_default_mcp_package_spec_falls_back_to_xmux_version_file(tmp_path):
    install_dir = tmp_path / "runtime-install"
    install_dir.mkdir()
    (install_dir / "xmux.zsh").write_text('XMUX_VERSION="2.3.4"\n', encoding="utf-8")

    package_spec = _node_call("default_mcp_package_spec", str(install_dir))

    assert package_spec == "xmux-bridge@2.3.4"


def test_path_with_xmux_bin_removes_stale_homebrew_xmux_bins():
    value = _node_call(
        "path_with_xmux_bin",
        "/opt/homebrew/Cellar/xmux/1.0.31/libexec",
        "/opt/homebrew/Cellar/xmux/1.0.2/libexec/bin:/opt/homebrew/bin:/usr/bin",
    )

    assert value == "/opt/homebrew/Cellar/xmux/1.0.31/libexec/bin:/opt/homebrew/bin:/usr/bin"


def test_homebrew_cellar_setup_targets_stable_opt_paths(tmp_path):
    codex_home = tmp_path / "codex-home"
    cellar, opt = _make_fake_homebrew_xmux_layout(tmp_path)

    result = _run_cli(
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(cellar),
            "--server-path",
            str(cellar / "xmux-lead-mcp-server.js"),
        ]
    )

    assert result.returncode == 0, result.stderr
    config = (codex_home / "config.toml").read_text(encoding="utf-8")
    assert f'args = ["{opt / "xmux-lead-mcp-server.js"}"]' in config
    assert f'PATH = "{opt}/bin:' in config
    assert f'XMUX_INSTALL_DIR = "{opt}"' in config
    assert str(cellar) not in config

    doctor = _run_cli(
        [
            "--doctor",
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(opt),
            "--server-path",
            str(opt / "xmux-lead-mcp-server.js"),
        ]
    )
    assert doctor.returncode == 0, doctor.stdout + doctor.stderr


def test_explicit_setup_writes_config_rules_without_implicit_skill_source(tmp_path):
    codex_home = tmp_path / "codex-home"
    server_path = ROOT / "xmux-lead-mcp-server.js"

    result = _run_cli(
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(ROOT),
            "--server-path",
            str(server_path),
        ]
    )

    assert result.returncode == 0, result.stderr
    config = (codex_home / "config.toml").read_text(encoding="utf-8")
    assert "[mcp_servers.xmux_lead]" in config
    assert f'args = ["{server_path}"]' in config
    assert f'PATH = "{ROOT}/bin:' in config
    assert f'XMUX_INSTALL_DIR = "{ROOT}"' in config
    assert "XMUX_PROJECT_DIR =" not in config
    assert "XMUX_STATE_DIR =" not in config
    assert "[marketplaces.xmux-local]" not in config
    assert '[plugins."xmux@xmux-local"]' not in config

    rules = (codex_home / "rules" / "default.rules").read_text(encoding="utf-8")
    assert 'prefix_rule(pattern=["xmux"], decision="allow")' in rules
    assert not (codex_home / "skills").exists()
    assert not (codex_home / "plugins" / "cache" / "xmux-local").exists()
    assert "skills: skipped; pass --skills-dir or set XMUX_CODEX_SKILLS_DIR" in result.stdout

    doctor = _run_cli(
        [
            "--doctor",
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(ROOT),
            "--server-path",
            str(server_path),
        ]
    )
    assert doctor.returncode == 0, doctor.stdout + doctor.stderr
    assert "no XMux skill source directory found" in doctor.stdout


def test_explicit_setup_removes_legacy_plugin_cache(tmp_path):
    codex_home = tmp_path / "codex-home"
    stale_cache = codex_home / "plugins" / "cache" / "xmux-local" / "xmux" / "local"
    stale_cache.mkdir(parents=True)
    (stale_cache / ".codex-plugin").mkdir()
    (stale_cache / ".codex-plugin" / "plugin.json").write_text("{}", encoding="utf-8")

    result = _run_cli(
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(ROOT),
            "--server-path",
            str(ROOT / "xmux-lead-mcp-server.js"),
        ]
    )

    assert result.returncode == 0, result.stderr
    config = (codex_home / "config.toml").read_text(encoding="utf-8")
    assert "[marketplaces.xmux-local]" not in config
    assert '[plugins."xmux@xmux-local"]' not in config
    assert not (codex_home / "plugins" / "cache" / "xmux-local").exists()
    assert "plugin_cache: disabled" in result.stdout


def test_explicit_setup_accepts_external_skills_dir_for_runtime_only_install(tmp_path):
    codex_home = tmp_path / "codex-home"
    install_dir = tmp_path / "runtime-install"
    install_dir.mkdir()
    skills_dir = tmp_path / "external-skills"
    skill = skills_dir / "xmux-external"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("name: xmux-external\n", encoding="utf-8")
    server_path = install_dir / "xmux-lead-mcp-server.js"

    result = _run_cli(
        [
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(install_dir),
            "--server-path",
            str(server_path),
            "--skills-dir",
            str(skills_dir),
        ]
    )

    assert result.returncode == 0, result.stderr
    installed = codex_home / "skills" / "xmux-external"
    assert (installed / "SKILL.md").is_file()
    assert (installed / ".xmux-managed-skill").read_text(encoding="utf-8").strip() == str(skill)
    assert not (codex_home / "plugins").exists()

    doctor = _run_cli(
        [
            "--doctor",
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            str(install_dir),
            "--server-path",
            str(server_path),
            "--skills-dir",
            str(skills_dir),
        ]
    )
    assert doctor.returncode == 0, doctor.stdout + doctor.stderr
    assert "XMux Codex skills installed under" in doctor.stdout


def test_remove_deletes_xmux_codex_assets_but_keeps_other_state(tmp_path):
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
        str(ROOT / "plugins" / "xmux" / "skills"),
    ]
    assert _run_cli(setup_args).returncode == 0

    other_skill = codex_home / "skills" / "other-skill"
    other_skill.mkdir()
    (other_skill / "SKILL.md").write_text("other\n", encoding="utf-8")
    user_xmux_skill = codex_home / "skills" / "xmux-user-skill"
    user_xmux_skill.mkdir()
    (user_xmux_skill / "SKILL.md").write_text("user owned\n", encoding="utf-8")

    assert (
        _run_cli(["--remove", "--home", str(codex_home), "--xmux-install-dir", str(ROOT)]).returncode
        == 0
    )

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


def test_ensure_codex_shell_environment_adds_xmux_wrapper_path():
    content = """
[shell_environment_policy.set]
TMPDIR = "/tmp/codex"
"""

    updated = _node_call("ensure_codex_shell_environment", content, "/repo/XMux")

    assert 'PATH = "/repo/XMux/bin:' in updated
    assert 'XMUX_INSTALL_DIR = "/repo/XMux"' in updated
    assert 'TMPDIR = "/tmp/codex"' in updated


def test_ensure_codex_shell_environment_deduplicates_xmux_wrapper_path():
    content = """
[shell_environment_policy.set]
PATH = "/usr/bin:/repo/XMux/bin:/bin"
XMUX_INSTALL_DIR = "/old"
"""

    updated = _node_call("ensure_codex_shell_environment", content, "/repo/XMux")

    assert 'PATH = "/repo/XMux/bin:/usr/bin:/bin"' in updated
    assert 'XMUX_INSTALL_DIR = "/repo/XMux"' in updated


def test_ensure_codex_shell_environment_removes_stale_xmux_bins(tmp_path):
    install_dir = tmp_path / "cellar" / "xmux" / "1.0.2" / "libexec"
    stale_checkout = tmp_path / "checkout"
    stale_worktree = tmp_path / "worktree"
    normal_bin = tmp_path / "normal" / "bin"

    for root in (install_dir, stale_checkout, stale_worktree):
        (root / "bin").mkdir(parents=True)
        (root / "xmux.zsh").write_text("# xmux\n", encoding="utf-8")
        (root / "bin" / "xmux").write_text("#!/bin/sh\n", encoding="utf-8")
    normal_bin.mkdir(parents=True)
    (normal_bin / "xmux").write_text("#!/bin/sh\n", encoding="utf-8")

    content = f"""
[shell_environment_policy.set]
PATH = "{stale_checkout / 'bin'}:{normal_bin}:{stale_worktree / 'bin'}:/usr/bin"
XMUX_INSTALL_DIR = "{stale_checkout}"
"""

    updated = _node_call("ensure_codex_shell_environment", content, str(install_dir))

    assert str(install_dir / "bin") in updated
    assert str(normal_bin) in updated
    assert str(stale_checkout / "bin") not in updated
    assert str(stale_worktree / "bin") not in updated
    assert f'XMUX_INSTALL_DIR = "{install_dir}"' in updated


def test_install_xmux_command_rule_is_marker_scoped(tmp_path):
    config_path = tmp_path / ".codex" / "config.toml"
    rules_path = tmp_path / ".codex" / "rules" / "default.rules"
    rules_path.parent.mkdir(parents=True)
    rules_path.write_text('prefix_rule(pattern=["pwd"], decision="allow")\n', encoding="utf-8")

    _node_call("install_xmux_command_rule", str(config_path))
    _node_call("install_xmux_command_rule", str(config_path))

    rules = rules_path.read_text(encoding="utf-8")
    assert rules.count('prefix_rule(pattern=["xmux"], decision="allow")') == 1
    assert 'prefix_rule(pattern=["pwd"], decision="allow")' in rules

    _node_call("remove_xmux_command_rule", str(config_path))

    rules = rules_path.read_text(encoding="utf-8")
    assert 'prefix_rule(pattern=["xmux"], decision="allow")' not in rules
    assert 'prefix_rule(pattern=["pwd"], decision="allow")' in rules


def test_xmux_lead_mcp_process_parser_extracts_server_paths():
    processes = _node_call(
        "_xmux_lead_mcp_processes_from_ps",
        """
          123 node /opt/homebrew/Cellar/xmux/1.0.2/libexec/xmux-lead-mcp-server.js
          456 node "/tmp/xmux dev/libexec/xmux-lead-mcp-server.js"
          789 node /tmp/other.js
        """,
    )

    assert [proc["pid"] for proc in processes] == ["123", "456"]
    assert processes[0]["server_path"] == (
        "/opt/homebrew/Cellar/xmux/1.0.2/libexec/xmux-lead-mcp-server.js"
    )
    assert processes[1]["server_path"] == "/tmp/xmux dev/libexec/xmux-lead-mcp-server.js"


def test_stale_xmux_lead_mcp_processes_warns_on_homebrew_mismatch():
    expected = "/opt/homebrew/Cellar/xmux/1.0.35/libexec/xmux-lead-mcp-server.js"

    stale = _node_call(
        "stale_xmux_lead_mcp_processes",
        expected,
        [
            {
                "pid": "123",
                "server_path": "/opt/homebrew/Cellar/xmux/1.0.2/libexec/xmux-lead-mcp-server.js",
            },
            {
                "pid": "456",
                "server_path": expected,
            },
            {
                "pid": "789",
                "server_path": str(ROOT / "xmux-lead-mcp-server.js"),
            },
        ],
    )

    assert [proc["pid"] for proc in stale] == ["123"]


def test_doctor_codex_warns_about_running_stale_homebrew_mcp_process(tmp_path):
    codex_home = tmp_path / "codex-home"
    config_path = codex_home / "config.toml"
    install_dir = "/opt/homebrew/Cellar/xmux/1.0.35/libexec"
    server_path = f"{install_dir}/xmux-lead-mcp-server.js"

    content = _node_call("ensure_codex_shell_environment", "", install_dir)
    content += "\n" + _node_call("build_block", server_path, install_dir)
    config_path.parent.mkdir(parents=True)
    config_path.write_text(content, encoding="utf-8")
    _node_call("install_xmux_command_rule", str(config_path))

    env = os.environ.copy()
    env["XMUX_TEST_PS_OUTPUT"] = (
        "123 node /opt/homebrew/Cellar/xmux/1.0.2/libexec/xmux-lead-mcp-server.js\n"
    )
    doctor = _run_cli(
        [
            "--doctor",
            "--home",
            str(codex_home),
            "--xmux-install-dir",
            install_dir,
            "--server-path",
            server_path,
        ],
        env=env,
    )

    assert doctor.returncode == 0, doctor.stdout + doctor.stderr
    assert "[OK] XMux Codex setup looks ready" in doctor.stdout
    assert "active xmux_lead MCP process pid 123 uses" in doctor.stdout
    assert "restart that Codex/XMux session" in doctor.stdout
