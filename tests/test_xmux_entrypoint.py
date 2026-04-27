import json
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
    result = run_zsh("xmux --help", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux sessions" in result.stderr
    assert "xmux doctor" in result.stderr
    assert "xmux bridge-status" in result.stderr
    assert "xmux recover" in result.stderr
    assert "xmux submit-test" in result.stderr
    assert "codex is not installed" not in result.stderr
    assert "tmux is not installed" not in result.stderr


def test_xmux_start_help_uses_same_entrypoint(tmp_path):
    result = run_zsh("xmux start --help", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux [start]" in result.stderr


def test_xmux_provider_help_uses_single_entrypoint(tmp_path):
    result = run_zsh("xmux claude --help", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "Usage: xmux claude -t <team>" in result.stderr
    assert "CLI not found" not in result.stderr


def test_xmux_unknown_subcommand_is_rejected(tmp_path):
    result = run_zsh("xmux nope", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode != 0
    assert "unknown xmux command 'nope'" in result.stderr


def test_xmux_codex_teammate_command_is_rejected(tmp_path):
    result = run_zsh("xmux codex", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode != 0
    assert "Codex teammates are unsupported" in result.stderr


def test_xmux_rejects_legacy_codex_teammate_flags(tmp_path):
    legacy_worker = "codex-" + "worker"
    for snippet in ("xmux start --codex", "xmux start -c", f"xmux start {legacy_worker}"):
        result = run_zsh(snippet, {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})
        assert result.returncode != 0
        assert "Codex teammates are unsupported" in result.stderr


def test_xmux_rejects_tmux_target_syntax_in_session_names(tmp_path):
    result = run_zsh("xmux start -n bad.name", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode != 0
    assert "invalid XMux tmux session name 'bad.name'" in result.stderr
    assert "codex is not installed" not in result.stderr


def test_default_xmux_state_dir_is_project_local_codex_xmux():
    result = run_zsh(
        'print -r -- "$XMUX_PROJECT_DIR"; print -r -- "$XMUX_STATE_DIR"; print -r -- "$(_xmux_team_dir demo)"',
        {"XMUX_PROJECT_DIR": None, "XMUX_STATE_DIR": None},
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.strip().splitlines()
    assert lines[0] == str(ROOT)
    assert lines[1] == str(ROOT / ".codex" / "xmux")
    assert lines[2] == str(ROOT / ".codex" / "xmux" / "teams" / "demo")


def test_default_xmux_state_dir_stays_at_project_root_from_subdirectory():
    result = run_zsh(
        'cd docs; xmux --help >/dev/null; print -r -- "$XMUX_STATE_DIR"',
        {"XMUX_PROJECT_DIR": None, "XMUX_STATE_DIR": None},
    )

    assert result.returncode == 0
    assert result.stdout.strip() == str(ROOT / ".codex" / "xmux")


def test_xmux_start_command_does_not_inject_isolated_codex_home():
    result = run_zsh(
        'print -r -- "$(_xmux_build_codex_env_command demo-team /tmp/xmux-demo-team -- --model gpt-5)"',
        {"XMUX_STATE_DIR": None},
    )

    assert result.returncode == 0, result.stderr
    codex_home = "CODEX_" + "HOME"
    assert f"env -u {codex_home}" in result.stdout
    assert f"XMUX_INSTALL_DIR={ROOT}" in result.stdout
    assert f"XMUX_PROJECT_DIR={ROOT}" in result.stdout
    assert f"XMUX_STATE_DIR={ROOT / '.codex' / 'xmux'}" in result.stdout
    assert "XMUX_DIR=" not in result.stdout
    assert "XMUX_HOME=" not in result.stdout
    assert "XMUX_TEAM=demo-team" in result.stdout
    assert "XMUX_TEAM_DIR=/tmp/xmux-demo-team" in result.stdout
    assert f"{codex_home}=" not in result.stdout
    assert ".codex-" + "home" not in result.stdout


def test_xmux_teammates_reads_state_dir_without_codex(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    result = run_zsh("xmux teammates -t demo", {"XMUX_STATE_DIR": str(state_dir)})

    assert result.returncode == 0, result.stderr
    assert "TEAM" in result.stdout
    assert "codex-lead" in result.stdout
    assert "worker-a" in result.stdout


def test_xmux_bridge_status_reads_metadata_without_raw_tmux(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    result = run_zsh("xmux bridge-status -t demo", {"XMUX_STATE_DIR": str(state_dir)})

    assert result.returncode == 0, result.stderr
    assert "TEAM" in result.stdout
    assert "worker-a" in result.stdout
    assert "gemini" in result.stdout
    assert "BRIDGE" in result.stdout


def test_xmux_tmux_wait_expected_sigterm_suppresses_143(tmp_path):
    result = run_zsh(
        "_xmux_tmux_wait_expected_sigterm",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == (
        'wait "$!"; rc=$?; case "$rc" in 0|143) exit 0 ;; '
        '*) exit "$rc" ;; esac'
    )


def test_xmux_stop_restores_lead_focus_before_and_after_kill(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team(
        "StopUX",
        "codex-lead",
        "codex",
        lead_pane="%1",
    )
    xmux_mailbox.register_member(
        "StopUX",
        "copilot-worker",
        "copilot",
        pane="%2",
    )

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-panes)
    printf '%%1\\n%%2\\n'
    ;;
  display-message)
    target=""
    fmt=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        -p)
          fmt="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ "$fmt" = '#{pane_id}' ]; then
      printf '%%2\\n'
    elif [ "$fmt" = '#{session_name}' ]; then
      printf 'StopUX\\n'
    elif [ "$fmt" = '#{@xmux-agent}' ]; then
      [ "$target" = '%%2' ] && printf 'copilot-worker\\n'
    elif [ "$fmt" = '#{@xmux-team}' ]; then
      [ "$target" = '%%2' ] && printf 'StopUX\\n'
    elif [ "$fmt" = '#{@xmux-lead}' ]; then
      [ "$target" = '%%1' ] && printf '1\\n'
    fi
    ;;
  select-pane|kill-pane)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    env = {
        "XMUX_STATE_DIR": str(state_dir),
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "TMUX": "fake",
        "TMUX_FAKE_LOG": str(log_path),
    }
    result = run_zsh("xmux stop -t StopUX copilot-worker", env)

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    first_select = lines.index("select-pane -t %1")
    kill_pane = lines.index("kill-pane -t %2")
    last_select = len(lines) - 1 - lines[::-1].index("select-pane -t %1")
    assert first_select < kill_pane < last_select


def test_xmux_prepare_gemini_mcp_writes_repo_local_bridge(tmp_path):
    home = tmp_path / "home"
    result = run_zsh(
        "_xmux_prepare_gemini_mcp",
        {"HOME": str(home), "XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    settings_path = home / ".gemini" / "settings.json"
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    assert settings["mcpServers"]["xmux_bridge"]["command"] == "node"
    assert settings["mcpServers"]["xmux_bridge"]["args"] == [
        str(ROOT / "bridge-mcp-server.js")
    ]


def test_xmux_gemini_model_env_aliases_default_to_auto(tmp_path):
    result = run_zsh(
        'XMUX_GEMINI_MODEL=default; _xmux_provider_env_assignments gemini',
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "GEMINI_MODEL=auto"


def test_xmux_gemini_model_env_is_opt_in(tmp_path):
    result = run_zsh(
        "_xmux_provider_env_assignments gemini",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == ""


def test_xmux_gemini_model_env_passes_alias_and_concrete_model(tmp_path):
    result = run_zsh(
        'XMUX_GEMINI_MODEL=pro; _xmux_provider_env_assignments gemini; '
        'XMUX_GEMINI_MODEL=gemini-3.1-pro-preview; '
        '_xmux_provider_env_assignments gemini',
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "GEMINI_MODEL=pro",
        "GEMINI_MODEL=gemini-3.1-pro-preview",
    ]


def test_xmux_gemini_model_env_does_not_override_explicit_model_args(tmp_path):
    result = run_zsh(
        'XMUX_GEMINI_MODEL=pro; '
        'print -r -- "long=$(_xmux_provider_env_assignments gemini --model flash)"; '
        'print -r -- "long_eq=$(_xmux_provider_env_assignments gemini --model=flash)"; '
        'print -r -- "short=$(_xmux_provider_env_assignments gemini -m flash)"; '
        'print -r -- "short_eq=$(_xmux_provider_env_assignments gemini -m=flash)"',
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "long=",
        "long_eq=",
        "short=",
        "short_eq=",
    ]


def test_xmux_doctor_summarizes_pending_requests_without_message_body(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
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
        {"XMUX_STATE_DIR": str(state_dir)},
    )

    assert result.returncode == 0, result.stderr
    assert "XMux doctor" in result.stdout
    assert "pending requests:" in result.stdout
    assert "id=req-doctor-001" in result.stdout
    assert "sensitive diagnostic prompt" not in result.stdout


def test_prepare_codex_runtime_uses_canonical_codex_home(tmp_path):
    home = tmp_path / "home"
    state_dir = tmp_path / ".xmux"
    home.mkdir()

    result = run_zsh(
        'team_dir="$XMUX_STATE_DIR/teams/demo"; _xmux_prepare_codex_runtime; '
        'print -r -- "$HOME/.codex/config.toml"; '
        '[[ ! -e "$team_dir/.codex-"home ]]',
        {"HOME": str(home), "XMUX_STATE_DIR": str(state_dir)},
    )

    assert result.returncode == 0, result.stderr
    config_path = Path(result.stdout.strip())

    config = config_path.read_text(encoding="utf-8")
    assert "[marketplaces.xmux-local]" in config
    assert f'source = "{ROOT}"' in config
    assert '[plugins."xmux@xmux-local"]' in config
    assert "[mcp_servers.xmux_lead]" in config
    assert f'XMUX_INSTALL_DIR = "{ROOT}"' in config
    assert f'XMUX_PROJECT_DIR = "{ROOT}"' in config
    assert f'XMUX_STATE_DIR = "{state_dir}"' in config
    assert "XMUX_DIR =" not in config
    assert "XMUX_HOME =" not in config
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
