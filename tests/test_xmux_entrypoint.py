import os
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import xmux_mailbox


ROOT = Path(__file__).resolve().parent.parent


def run_zsh(snippet, env=None):
    zsh = shutil.which("zsh")
    assert zsh is not None
    full_env = os.environ.copy()
    if env:
        for key, value in env.items():
            if value is None:
                full_env.pop(key, None)
            else:
                full_env[key] = value
    return subprocess.run(
        [zsh, "-f", "-c", f"source {ROOT / 'xmux.zsh'}\n{snippet}"],
        cwd=ROOT,
        env=full_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_xmux_help_does_not_require_tmux_or_codex(tmp_path):
    result = run_zsh("xmux --help", {"XMUX_HOME": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux sessions" in result.stderr
    assert "xmux doctor" in result.stderr
    assert "xmux bridge-status" in result.stderr
    assert "xmux recover" in result.stderr
    assert "xmux submit-test" in result.stderr
    assert "codex is not installed" not in result.stderr
    assert "tmux is not installed" not in result.stderr


def test_xmux_start_help_uses_same_entrypoint(tmp_path):
    result = run_zsh("xmux start --help", {"XMUX_HOME": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux [start]" in result.stderr


def test_xmux_provider_help_uses_single_entrypoint(tmp_path):
    result = run_zsh("xmux claude --help", {"XMUX_HOME": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "Usage: xmux claude -t <team>" in result.stderr
    assert "CLI not found" not in result.stderr


def test_xmux_unknown_subcommand_is_rejected(tmp_path):
    result = run_zsh("xmux nope", {"XMUX_HOME": str(tmp_path / ".xmux")})

    assert result.returncode != 0
    assert "unknown xmux command 'nope'" in result.stderr


def test_xmux_codex_teammate_command_is_rejected(tmp_path):
    result = run_zsh("xmux codex", {"XMUX_HOME": str(tmp_path / ".xmux")})

    assert result.returncode != 0
    assert "Codex teammates are unsupported" in result.stderr


def test_xmux_rejects_legacy_codex_teammate_flags(tmp_path):
    legacy_worker = "codex-" + "worker"
    for snippet in ("xmux start --codex", "xmux start -c", f"xmux start {legacy_worker}"):
        result = run_zsh(snippet, {"XMUX_HOME": str(tmp_path / ".xmux")})
        assert result.returncode != 0
        assert "Codex teammates are unsupported" in result.stderr


def test_xmux_rejects_tmux_target_syntax_in_session_names(tmp_path):
    result = run_zsh("xmux start -n bad.name", {"XMUX_HOME": str(tmp_path / ".xmux")})

    assert result.returncode != 0
    assert "invalid XMux tmux session name 'bad.name'" in result.stderr
    assert "codex is not installed" not in result.stderr


def test_default_xmux_home_is_project_local_codex_xmux():
    result = run_zsh(
        'print -r -- "$XMUX_HOME"; print -r -- "$(_xmux_team_dir demo)"',
        {"XMUX_HOME": None},
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.strip().splitlines()
    assert lines[0] == str(ROOT / ".codex" / "xmux")
    assert lines[1] == str(ROOT / ".codex" / "xmux" / "teams" / "demo")


def test_default_xmux_home_stays_at_project_root_from_subdirectory():
    result = run_zsh(
        'cd docs; xmux --help >/dev/null; print -r -- "$XMUX_HOME"',
        {"XMUX_HOME": None},
    )

    assert result.returncode == 0
    assert result.stdout.strip() == str(ROOT / ".codex" / "xmux")


def test_xmux_start_command_does_not_inject_isolated_codex_home():
    result = run_zsh(
        'print -r -- "$(_xmux_build_codex_env_command demo-team /tmp/xmux-demo-team -- --model gpt-5)"',
        {"XMUX_HOME": None},
    )

    assert result.returncode == 0, result.stderr
    codex_home = "CODEX_" + "HOME"
    assert f"env -u {codex_home}" in result.stdout
    assert "XMUX_TEAM=demo-team" in result.stdout
    assert "XMUX_TEAM_DIR=/tmp/xmux-demo-team" in result.stdout
    assert f"{codex_home}=" not in result.stdout
    assert ".codex-" + "home" not in result.stdout


def test_xmux_teammates_reads_xmux_home_without_codex(tmp_path, monkeypatch):
    xmux_home = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_HOME", str(xmux_home))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    result = run_zsh("xmux teammates -t demo", {"XMUX_HOME": str(xmux_home)})

    assert result.returncode == 0, result.stderr
    assert "TEAM" in result.stdout
    assert "codex-lead" in result.stdout
    assert "worker-a" in result.stdout


def test_xmux_bridge_status_reads_metadata_without_raw_tmux(tmp_path, monkeypatch):
    xmux_home = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_HOME", str(xmux_home))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    result = run_zsh("xmux bridge-status -t demo", {"XMUX_HOME": str(xmux_home)})

    assert result.returncode == 0, result.stderr
    assert "TEAM" in result.stdout
    assert "worker-a" in result.stdout
    assert "gemini" in result.stdout
    assert "BRIDGE" in result.stdout


def test_xmux_doctor_summarizes_pending_requests_without_message_body(
    tmp_path, monkeypatch
):
    xmux_home = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_HOME", str(xmux_home))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")
    xmux_mailbox.enqueue_request(
        "demo",
        "worker-a",
        from_name="codex-lead",
        message="sensitive diagnostic prompt",
        request_id="req-doctor-001",
    )

    result = run_zsh(
        "xmux doctor -t demo --log-lines 0",
        {"XMUX_HOME": str(xmux_home)},
    )

    assert result.returncode == 0, result.stderr
    assert "XMux doctor" in result.stdout
    assert "pending requests:" in result.stdout
    assert "id=req-doctor-001" in result.stdout
    assert "sensitive diagnostic prompt" not in result.stdout


def test_prepare_codex_runtime_uses_canonical_codex_home(tmp_path):
    home = tmp_path / "home"
    xmux_home = tmp_path / ".xmux"
    home.mkdir()

    result = run_zsh(
        'team_dir="$XMUX_HOME/teams/demo"; _xmux_prepare_codex_runtime; '
        'print -r -- "$HOME/.codex/config.toml"; '
        '[[ ! -e "$team_dir/.codex-"home ]]',
        {"HOME": str(home), "XMUX_HOME": str(xmux_home)},
    )

    assert result.returncode == 0, result.stderr
    config_path = Path(result.stdout.strip())

    config = config_path.read_text(encoding="utf-8")
    assert "[marketplaces.xmux-local]" in config
    assert f'source = "{ROOT}"' in config
    assert '[plugins."xmux@xmux-local"]' in config
    assert "[mcp_servers.xmux_lead]" in config
    assert f'XMUX_HOME = "{xmux_home}"' in config
    assert "enabled = true" in config
    assert "CODEX_" + "HOME" not in config

    plugin_cache = home / ".codex" / "plugins" / "cache" / "xmux-local" / "xmux" / "local"
    assert (plugin_cache / ".codex-plugin" / "plugin.json").is_file()
    if plugin_cache.is_symlink():
        assert plugin_cache.resolve() == ROOT / "plugins" / "xmux"


def test_xmux_plugin_exposes_slash_command():
    assert (ROOT / ".agents" / "plugins" / "marketplace.json").is_file()
    assert (ROOT / "plugins" / "xmux" / ".codex-plugin" / "plugin.json").is_file()
    for command in (
        "xmux-teams",
        "xmux-phase",
        "xmux-veto",
        "xmux-claude",
        "xmux-gemini",
        "xmux-copilot",
        "xmux-tools",
    ):
        assert (ROOT / "plugins" / "xmux" / "commands" / f"{command}.md").is_file()


def test_xmux_plugin_exposes_xmux_commands_only():
    plugin_files = list((ROOT / "plugins" / "xmux" / "commands").glob("*.md"))
    plugin_files += list((ROOT / "plugins" / "xmux" / "skills").glob("*/SKILL.md"))
    text = "\n".join(path.read_text(encoding="utf-8") for path in plugin_files)

    assert "/a" + "mux-" not in text
    assert "/cl" + "mux-" not in text
    assert "name: a" + "mux-" not in text
    assert "name: cl" + "mux-" not in text
    assert "/xmux-codex" not in text
    assert "name: xmux-codex" not in text
