import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"


class NodeMailbox:
    def _json(self, *args):
        result = subprocess.run(
            ["node", str(MAILBOX), *args],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)

    def init_team(self, team, lead_name, lead_provider, lead_pane=None):
        args = [
            "init-team",
            team,
            "--lead-name",
            lead_name,
            "--lead-provider",
            lead_provider,
        ]
        if lead_pane is not None:
            args.extend(["--lead-pane", lead_pane])
        return self._json(*args)

    def register_member(self, team, name, provider, pane=None, backend="tmux"):
        args = [
            "register-member",
            team,
            name,
            "--provider",
            provider,
            "--backend",
            backend,
        ]
        if pane is not None:
            args.extend(["--pane", pane])
        return self._json(*args)

    def enqueue_request(self, team, to, from_name, message, request_id=None):
        args = [
            "enqueue-request",
            team,
            to,
            "--from",
            from_name,
            "--message",
            message,
        ]
        if request_id is not None:
            args.extend(["--request-id", request_id])
        return self._json(*args)


xmux_mailbox = NodeMailbox()


def bridge_pid_meta(team, agent, kind, pid, install_dir, state_dir, project_dir=ROOT):
    return (
        f"team={team}\n"
        f"agent={agent}\n"
        f"kind={kind}\n"
        f"install_dir={install_dir}\n"
        f"project_dir={project_dir}\n"
        f"state_dir={state_dir}\n"
        f"pid={pid}\n"
    )


def make_brew_libexec_layout(tmp_path):
    libexec = tmp_path / "libexec"
    libexec.mkdir()
    for filename in (
        "xmux.zsh",
        "xmux-bridge.zsh",
        "bridge-mcp-server.js",
        "xmux-lead-mcp-server.js",
    ):
        shutil.copy2(ROOT / filename, libexec / filename)
    for dirname in ("bin", "scripts", "prompt", "share"):
        src = ROOT / dirname
        if src.exists():
            shutil.copytree(src, libexec / dirname)
    return libexec


def make_homebrew_cellar_and_opt_layout(tmp_path):
    prefix = tmp_path / "homebrew"
    cellar = prefix / "Cellar" / "xmux" / "1.0.35" / "libexec"
    opt = prefix / "opt" / "xmux" / "libexec"
    for root in (cellar, opt):
        root.mkdir(parents=True)
        for filename in ("xmux.zsh", "bridge-mcp-server.js", "xmux-lead-mcp-server.js"):
            shutil.copy2(ROOT / filename, root / filename)
    return cellar, opt


def run_zsh(snippet, env=None):
    zsh = shutil.which("zsh")
    assert zsh is not None
    full_env = os.environ.copy()
    for key in ("XMUX_INSTALL_DIR", "XMUX_PROJECT_DIR", "XMUX_STATE_DIR", "XMUX_ACTIVE_TEAM_REGISTRY_DIR"):
        full_env.pop(key, None)
    if env:
        for key, value in env.items():
            if value is None:
                full_env.pop(key, None)
            else:
                full_env[key] = value
    if full_env.get("XMUX_STATE_DIR") and not full_env.get("XMUX_ACTIVE_TEAM_REGISTRY_DIR"):
        full_env["XMUX_ACTIVE_TEAM_REGISTRY_DIR"] = str(
            Path(full_env["XMUX_STATE_DIR"]) / "active-teams"
        )
    return subprocess.run(
        [zsh, "-f", "-c", f"source {ROOT / 'xmux.zsh'}\n{snippet}"],
        cwd=ROOT,
        env=full_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def run_xmux_bin(args, env=None, cwd=ROOT):
    full_env = os.environ.copy()
    for key in ("XMUX_INSTALL_DIR", "XMUX_PROJECT_DIR", "XMUX_STATE_DIR", "XMUX_ACTIVE_TEAM_REGISTRY_DIR"):
        full_env.pop(key, None)
    if env:
        for key, value in env.items():
            if value is None:
                full_env.pop(key, None)
            else:
                full_env[key] = value
    if full_env.get("XMUX_STATE_DIR") and not full_env.get("XMUX_ACTIVE_TEAM_REGISTRY_DIR"):
        full_env["XMUX_ACTIVE_TEAM_REGISTRY_DIR"] = str(
            Path(full_env["XMUX_STATE_DIR"]) / "active-teams"
        )
    return subprocess.run(
        [str(ROOT / "bin" / "xmux"), *args],
        cwd=cwd,
        env=full_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_xmux_zsh_removes_inline_python_and_mailbox_py_dependency():
    content = (ROOT / "xmux.zsh").read_text(encoding="utf-8")
    assert "python3 -" not in content
    assert "scripts/xmux_mailbox.py" not in content


def test_xmux_help_does_not_require_tmux_or_codex(tmp_path):
    result = run_zsh("xmux --help", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux start" in result.stderr
    assert "xmux setup-codex" in result.stderr
    assert "xmux doctor-codex" in result.stderr
    assert "xmux remove-codex" in result.stderr
    assert "xmux theme-reset" in result.stderr
    assert "xmux --version" in result.stderr
    assert "xmux help agent" in result.stderr
    assert "xmux teamCreate" not in result.stderr
    assert "xmux teammateAdd" not in result.stderr
    assert "xmux sessions" not in result.stderr
    assert "xmux ensure" not in result.stderr
    assert "xmux bridgeStatus" not in result.stderr
    assert "xmux submit-test" not in result.stderr
    assert "codex is not installed" not in result.stderr
    assert "tmux is not installed" not in result.stderr


def test_xmux_executable_entrypoint_does_not_require_zshrc(tmp_path):
    result = run_xmux_bin(["--help"], {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux start" in result.stderr
    assert "xmux teamCreate" not in result.stderr
    assert "zshrc" not in result.stderr.lower()


def test_xmux_version_does_not_start_team_or_require_runtime(tmp_path):
    result = run_xmux_bin(["--version"], {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert result.stdout == "xmux 1.0.40\n"
    assert result.stderr == ""


def test_xmux_provider_brand_colors_are_stable(tmp_path):
    result = run_zsh(
        """
print -r -- "$(_xmux_provider_brand_color codex)"
print -r -- "$(_xmux_provider_brand_color claude)"
print -r -- "$(_xmux_provider_brand_color gemini)"
print -r -- "$(_xmux_provider_brand_color copilot)"
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "#10A37F",
        "#D97757",
        "#4285F4",
        "#8534F3",
    ]


def test_xmux_terminal_codex_theme_sequences_are_stable(tmp_path):
    result = run_zsh(
        "_xmux_apply_terminal_codex_theme; _xmux_reset_terminal_theme",
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "XMUX_TERMINAL_THEME_FORCE": "1",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "\033]10;#F5F7FA\033\\" in result.stdout
    assert "\033]11;#0E0F12\033\\" in result.stdout
    assert "\033]12;#10A37F\033\\" in result.stdout
    assert "\033]4;2;#10A37F\033\\" in result.stdout
    assert "\033]4;4;#4285F4\033\\" in result.stdout
    assert "\033]4;5;#8534F3\033\\" in result.stdout
    assert result.stdout.endswith(
        "\033]110\033\\"
        "\033]111\033\\"
        "\033]112\033\\"
        "\033]104\033\\"
        "\033]105\033\\"
    )


def test_xmux_terminal_theme_can_be_disabled(tmp_path):
    result = run_zsh(
        '_xmux_with_terminal_codex_theme print -r -- "inside-theme"',
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "XMUX_TERMINAL_THEME": "0",
            "XMUX_TERMINAL_THEME_FORCE": "1",
        },
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == "inside-theme\n"


def test_xmux_theme_reset_command_emits_reset_sequences(tmp_path):
    result = run_zsh(
        "xmux theme-reset",
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "XMUX_TERMINAL_THEME_FORCE": "1",
        },
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == (
        "\033]110\033\\"
        "\033]111\033\\"
        "\033]112\033\\"
        "\033]104\033\\"
        "\033]105\033\\"
    )


def test_xmux_help_topics_expose_hidden_agent_and_debug_commands(tmp_path):
    env = {"XMUX_STATE_DIR": str(tmp_path / ".xmux")}
    agent = run_zsh("xmux help agent", env)
    debug = run_zsh("xmux help debug", env)

    assert agent.returncode == 0
    assert "xmux teamCreate" in agent.stderr
    assert "xmux teammateAdd" in agent.stderr
    assert "xmux teamShutdown" in agent.stderr
    assert "xmux sessions" not in agent.stderr

    assert debug.returncode == 0
    assert "xmux sessions" in debug.stderr
    assert "xmux ensure" in debug.stderr
    assert "xmux bridgeStatus" in debug.stderr
    assert "xmux sendPane" in debug.stderr
    assert "xmux submit-test" not in debug.stderr


def test_xmux_executable_works_from_brew_libexec_layout(tmp_path):
    libexec = make_brew_libexec_layout(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    (project / ".git").mkdir()

    env = os.environ.copy()
    for key in ("XMUX_PROJECT_DIR", "XMUX_STATE_DIR"):
        env.pop(key, None)
    env["XMUX_INSTALL_DIR"] = str(libexec)

    result = subprocess.run(
        [str(libexec / "bin" / "xmux"), "--help"],
        cwd=project,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert result.returncode == 0
    assert "xmux start" in result.stderr
    assert str(ROOT) not in result.stdout + result.stderr


def test_brew_libexec_layout_keeps_state_project_local(tmp_path):
    zsh = shutil.which("zsh")
    assert zsh is not None
    libexec = make_brew_libexec_layout(tmp_path)
    project = tmp_path / "project"
    project.mkdir()
    (project / ".git").mkdir()

    env = os.environ.copy()
    for key in ("XMUX_PROJECT_DIR", "XMUX_STATE_DIR"):
        env.pop(key, None)
    env["XMUX_INSTALL_DIR"] = str(libexec)

    result = subprocess.run(
        [
            zsh,
            "-f",
            "-c",
            "\n".join(
                [
                    f"source {libexec / 'xmux.zsh'}",
                    'print -r -- "$XMUX_INSTALL_DIR"',
                    'print -r -- "$XMUX_PROJECT_DIR"',
                    'print -r -- "$XMUX_STATE_DIR"',
                    "xmux --help >/dev/null",
                ]
            ),
        ],
        cwd=project,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        str(libexec),
        str(project),
        str(project / ".codex" / "xmux"),
    ]


def test_homebrew_cellar_runtime_targets_stable_opt_for_mcp_configs(tmp_path):
    cellar, opt = make_homebrew_cellar_and_opt_layout(tmp_path)

    result = run_zsh(
        "\n".join(
            [
                "_xmux_mcp_install_dir",
                "_xmux_mcp_bridge_path",
                "_xmux_mcp_lead_path",
            ]
        ),
        {"XMUX_INSTALL_DIR": str(cellar)},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        str(opt),
        str(opt / "bridge-mcp-server.js"),
        str(opt / "xmux-lead-mcp-server.js"),
    ]


def test_xmux_executable_entrypoint_supports_role_command_help(tmp_path):
    result = run_xmux_bin(
        ["teamCreate", "--help"],
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0
    assert "Usage: xmux teamCreate" in result.stdout + result.stderr


def test_xmux_plugin_executable_entrypoint_supports_role_command_help(tmp_path):
    result = subprocess.run(
        [str(ROOT / "plugins" / "xmux" / "bin" / "xmux"), "teamCreate", "--help"],
        cwd=ROOT,
        env={
            **os.environ,
            "XMUX_INSTALL_DIR": str(ROOT),
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
        },
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert result.returncode == 0
    assert "Usage: xmux teamCreate" in result.stdout + result.stderr


def test_xmux_plugin_executable_requires_install_dir_or_marker(tmp_path):
    plugin_dir = tmp_path / "local"
    bin_dir = plugin_dir / "bin"
    bin_dir.mkdir(parents=True)
    shutil.copy2(ROOT / "plugins" / "xmux" / "bin" / "xmux", bin_dir / "xmux")
    shutil.copy2(ROOT / "xmux.zsh", plugin_dir / "xmux.zsh")

    result = subprocess.run(
        [str(bin_dir / "xmux"), "teamCreate", "--help"],
        cwd=tmp_path,
        env={
            **os.environ,
            "XMUX_INSTALL_DIR": "",
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
        },
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert result.returncode == 127
    assert "cannot locate XMux install directory" in result.stderr


def test_xmux_plugin_executable_can_source_install_marker(tmp_path):
    plugin_dir = tmp_path / "local"
    bin_dir = plugin_dir / "bin"
    bin_dir.mkdir(parents=True)
    shutil.copy2(ROOT / "plugins" / "xmux" / "bin" / "xmux", bin_dir / "xmux")
    (plugin_dir / ".xmux-install-dir").write_text(f"{ROOT}\n", encoding="utf-8")

    result = subprocess.run(
        [str(bin_dir / "xmux"), "teamCreate", "--help"],
        cwd=tmp_path,
        env={
            **os.environ,
            "XMUX_INSTALL_DIR": "",
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
        },
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert result.returncode == 0
    assert "Usage: xmux teamCreate" in result.stdout + result.stderr


def test_xmux_start_help_uses_same_entrypoint(tmp_path):
    result = run_zsh("xmux start --help", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "xmux start" in result.stderr
    assert "xmux teamCreate" not in result.stderr


def test_xmux_provider_help_uses_single_entrypoint(tmp_path):
    result = run_zsh("xmux claude --help", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    assert "Usage: xmux claude -t <team>" in result.stderr
    assert "CLI not found" not in result.stderr


def test_xmux_role_command_help_does_not_require_tmux_or_codex(tmp_path):
    for command in (
        "teamCreate",
        "teammateAdd",
        "teamStatus",
        "teammateStatus",
        "teammateShutdown",
        "teamShutdown",
    ):
        result = run_zsh(
            f"xmux {command} --help",
            {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
        )

        assert result.returncode == 0, result.stderr
        assert f"Usage: xmux {command}" in result.stdout + result.stderr
        assert "codex is not installed" not in result.stderr
        assert "tmux is not installed" not in result.stderr


def test_xmux_send_pane_help_replaces_send_alias(tmp_path):
    env = {"XMUX_STATE_DIR": str(tmp_path / ".xmux")}

    send_pane = run_zsh("xmux sendPane --help", env)
    old_send = run_zsh("xmux send --help", env)

    assert send_pane.returncode == 0
    assert "Usage: xmux sendPane <target>" in send_pane.stdout + send_pane.stderr
    assert old_send.returncode == 1
    assert "unknown xmux command 'send'" in old_send.stderr


def test_xmux_removed_aliases_fail_with_user_help(tmp_path):
    env = {"XMUX_STATE_DIR": str(tmp_path / ".xmux")}
    removed_aliases = (
        "team-create",
        "teammate-add",
        "team-status",
        "teammate-status",
        "teammate-shutdown",
        "team-shutdown",
        "pane-info",
        "bridge-status",
        "submit-test",
        "send",
        "setupCodex",
        "doctorCodex",
        "removeCodex",
        "team",
        "pane",
        "bridge",
        "focus",
        "status",
    )

    for alias in removed_aliases:
        result = run_zsh(f"xmux {alias} --help", env)

        assert result.returncode == 1, alias
        assert f"unknown xmux command '{alias}'" in result.stderr
        assert "xmux help agent" in result.stderr


def test_xmux_hidden_aliases_are_not_listed_in_split_help(tmp_path):
    result = run_zsh("xmux help all", {"XMUX_STATE_DIR": str(tmp_path / ".xmux")})

    assert result.returncode == 0
    text = result.stdout + result.stderr
    for hidden_alias in (
        "team-create",
        "teammate-add",
        "team-status",
        "teammate-status",
        "teammate-shutdown",
        "team-shutdown",
        "pane-info",
        "bridge-status",
        "submit-test",
        "setupCodex",
        "doctorCodex",
        "removeCodex",
    ):
        assert hidden_alias not in text


def test_xmux_completion_top_level_hides_agent_debug_and_alias_commands():
    completion = ROOT / "share" / "zsh" / "site-functions" / "_xmux"
    text = completion.read_text(encoding="utf-8")
    command_list = text.split("commands=(", 1)[1].split(")", 1)[0]
    command_names = {
        line.strip().strip('"').split(":", 1)[0]
        for line in command_list.splitlines()
        if line.strip().startswith('"')
    }

    for visible_command in (
        "start",
        "setup-codex",
        "doctor-codex",
        "remove-codex",
        "theme-reset",
        "help",
    ):
        assert visible_command in command_names

    for hidden_command in (
        "teamCreate",
        "teammateAdd",
        "teamStatus",
        "teammateStatus",
        "teammateShutdown",
        "teamShutdown",
        "teammates",
        "ensure",
        "sessions",
        "paneInfo",
        "doctor",
        "bridgeStatus",
        "recover",
        "sendPane",
        "send",
        "attach",
        "shutdown",
        "claude",
        "gemini",
        "copilot",
        "team-create",
        "teammate-add",
        "team-status",
        "teammate-status",
        "teammate-shutdown",
        "team-shutdown",
    ):
        assert hidden_command not in command_names


def test_xmux_team_create_maps_with_providers_to_start(tmp_path):
    result = run_zsh(
        """
_xmux_start() {
  printf '<%s>\\n' "$@"
}
xmux teamCreate -t demo -n demo-session gemini copilot --keep-team-on-lead-exit -- --model gpt-5
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "<-n>",
        "<demo-session>",
        "<-T>",
        "<demo>",
        "<--keep-team-on-lead-exit>",
        "<--gemini>",
        "<--copilot>",
        "<-->",
        "<--model>",
        "<gpt-5>",
    ]


def test_xmux_team_create_rejects_comma_separated_providers(tmp_path):
    result = run_zsh(
        """
_xmux_start() {
  print -r -- should-not-start
}
xmux teamCreate -t demo gemini,copilot
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 1
    assert result.stdout == ""
    assert "provider names must be space-separated" in result.stderr


def test_xmux_team_create_accepts_with_option_for_space_separated_compatibility(
    tmp_path,
):
    result = run_zsh(
        """
_xmux_start() {
  printf '<%s>\\n' "$@"
}
xmux teamCreate -t demo --with gemini copilot
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "<-T>",
        "<demo>",
        "<--gemini>",
        "<--copilot>",
    ]


def test_xmux_team_create_rejects_comma_separated_with_option(tmp_path):
    result = run_zsh(
        """
_xmux_start() {
  print -r -- should-not-start
}
xmux teamCreate -t demo --with gemini,copilot
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 1
    assert result.stdout == ""
    assert "provider names must be space-separated" in result.stderr


def test_xmux_teammate_add_maps_providers_to_default_wrappers(tmp_path):
    result = run_zsh(
        """
xmux-gemini() {
  printf 'gemini'
  printf ' <%s>' "$@"
  printf '\\n'
}
xmux-copilot() {
  printf 'copilot'
  printf ' <%s>' "$@"
  printf '\\n'
}
xmux teammateAdd -t demo --session demo-session gemini copilot
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "gemini <-t> <demo> <-s> <demo-session>",
        "copilot <-t> <demo> <-s> <demo-session>",
    ]


def test_xmux_role_shutdown_commands_map_to_shutdown_scope(tmp_path):
    result = run_zsh(
        """
_xmux_cmd_shutdown() {
  printf '<%s>\\n' "$@"
}
xmux teammateShutdown -t demo gemini-worker copilot-worker --timeout 0 --reason refresh
print -r -- ---
xmux teamShutdown -t demo --timeout 0 --reason done
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "<-t>",
        "<demo>",
        "<--agent>",
        "<gemini-worker>",
        "<--agent>",
        "<copilot-worker>",
        "<--timeout>",
        "<0>",
        "<--reason>",
        "<refresh>",
        "---",
        "<-t>",
        "<demo>",
        "<--timeout>",
        "<0>",
        "<--reason>",
        "<done>",
    ]


def test_xmux_teammate_status_maps_to_bridge_status(tmp_path):
    result = run_zsh(
        """
_xmux_cmd_bridge_status() {
  printf '<%s>\\n' "$@"
}
xmux teammateStatus -t demo gemini-worker
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["<-t>", "<demo>", "<gemini-worker>"]


def test_xmux_team_status_maps_to_teammates(tmp_path):
    result = run_zsh(
        """
_xmux_cmd_teammates() {
  printf '<%s>\\n' "$@"
}
xmux teamStatus -t demo
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["<-t>", "<demo>"]


def test_xmux_team_status_without_team_uses_current_pane_tag(tmp_path):
    result = run_zsh(
        """
_xmux_current_team() {
  print -r -- demo
}
_xmux_cmd_teammates() {
  printf '<%s>\\n' "$@"
}
xmux teamStatus
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["<-t>", "<demo>"]


def test_xmux_team_status_without_current_team_fails_without_scanning(tmp_path):
    result = run_zsh(
        """
_xmux_current_team() {
  return 0
}
_xmux_cmd_teammates() {
  print -r -- should-not-scan
}
xmux teamStatus
""",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 1
    assert "cannot determine current XMux team" in result.stderr
    assert result.stdout == ""


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
    assert f"PATH={ROOT / 'bin'}:" in result.stdout
    assert f"XMUX_INSTALL_DIR={ROOT}" in result.stdout
    assert f"XMUX_PROJECT_DIR={ROOT}" in result.stdout
    assert f"XMUX_STATE_DIR={ROOT / '.codex' / 'xmux'}" in result.stdout
    assert "XMUX_DIR=" not in result.stdout
    assert "XMUX_HOME=" not in result.stdout
    assert "XMUX_TEAM=demo-team" in result.stdout
    assert "XMUX_TEAM_DIR=/tmp/xmux-demo-team" in result.stdout
    assert "XMUX_SHUTDOWN_ON_LEAD_EXIT=1" in result.stdout
    assert "_xmux_run_codex_lead" in result.stdout
    assert f"{codex_home}=" not in result.stdout
    assert ".codex-" + "home" not in result.stdout


def test_xmux_runtime_env_assignments_deduplicates_install_bin(tmp_path):
    result = run_zsh(
        'print -r -- "$(_xmux_runtime_env_assignments)"',
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "PATH": f"{ROOT / 'bin'}:/usr/bin:/bin",
        },
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.count(str(ROOT / "bin")) == 1
    assert f"PATH={ROOT / 'bin'}:/usr/bin:/bin" in result.stdout


def test_xmux_start_command_can_keep_team_on_lead_exit(tmp_path):
    result = run_zsh(
        'print -r -- "$(_xmux_build_codex_env_command demo-team /tmp/xmux-demo-team 0 --)"',
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 0, result.stderr
    assert "XMUX_SHUTDOWN_ON_LEAD_EXIT=0" in result.stdout


def test_xmux_team_create_with_tmux_env_and_non_tty_starts_detached_session(
    tmp_path,
):
    state_dir = tmp_path / ".xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    session_created = tmp_path / "session-created"

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    [ -f "$TMUX_FAKE_SESSION_CREATED" ]
    ;;
  new-session)
    touch "$TMUX_FAKE_SESSION_CREATED"
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  set-option|select-pane)
    ;;
  attach-session)
    printf 'attach-session should not run in non-TTY mode\\n' >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux teamCreate -t demo -n demo-session",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": "fake-tmux-env",
            "TMUX_PANE": "%current",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_CREATED": str(session_created),
        },
    )

    assert result.returncode == 0, result.stderr
    assert (
        "team created team:demo session:demo-session detached:true name:XMux/demo-session"
        in result.stdout
    )
    assert (state_dir / "teams" / "demo" / "team.json").is_file()
    registry = json.loads(
        (state_dir / "active-teams" / "demo.json").read_text(encoding="utf-8")
    )
    assert registry["schema"] == "xmux.active_team.v1"
    assert registry["team"] == "demo"
    assert registry["project_dir"] == str(ROOT)
    assert registry["state_dir"] == str(state_dir)
    assert registry["team_dir"] == str(state_dir / "teams" / "demo")
    assert registry["session"] == "demo-session"
    assert registry["lead_pane"] == "%1"
    assert registry["status"] == "active"
    log_lines = log_path.read_text(encoding="utf-8").splitlines()
    assert any(line.startswith("new-session ") for line in log_lines)
    assert not any(line.startswith("attach-session ") for line in log_lines)
    assert not any(line == "display-message -p #S" for line in log_lines)


def test_xmux_bin_team_create_outside_tmux_handles_unset_tmux_with_nounset(tmp_path):
    state_dir = tmp_path / ".xmux"
    home = tmp_path / "home"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    home.mkdir()
    log_path = tmp_path / "tmux.log"
    session_created = tmp_path / "session-created"

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    [ -f "$TMUX_FAKE_SESSION_CREATED" ]
    ;;
  new-session)
    touch "$TMUX_FAKE_SESSION_CREATED"
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  set-option|select-pane)
    ;;
  attach-session)
    printf 'attach-session should not run in non-TTY mode\\n' >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["teamCreate", "-t", "demo", "-n", "demo-session"],
        {
            "HOME": str(home),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_CREATED": str(session_created),
        },
    )

    assert result.returncode == 0, result.stderr
    assert "TMUX: parameter not set" not in result.stderr
    assert (
        "team created team:demo session:demo-session detached:true name:XMux/demo-session"
        in result.stdout
    )


def test_xmux_non_tty_starts_detached_without_theme_sequences(tmp_path):
    state_dir = tmp_path / ".xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    session_created = tmp_path / "session-created"

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    [ -f "$TMUX_FAKE_SESSION_CREATED" ]
    ;;
  new-session)
    touch "$TMUX_FAKE_SESSION_CREATED"
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  set-option|set-window-option|select-pane)
    ;;
  attach-session)
    printf 'attach-session should not run in non-TTY mode\\n' >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux -T demo -n demo-session",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_CREATED": str(session_created),
        },
    )

    assert result.returncode == 0, result.stderr
    assert (
        result.stdout
        == "[xmux] team created team:demo session:demo-session detached:true name:XMux/demo-session\n"
    )
    assert "\033]" not in result.stdout
    assert "\033]" not in result.stderr
    log_lines = log_path.read_text(encoding="utf-8").splitlines()
    assert any(line.startswith("new-session ") for line in log_lines)
    assert not any(line.startswith("attach-session ") for line in log_lines)


def test_xmux_short_name_uses_project_scoped_display_name_and_internal_session(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    session_created = tmp_path / "session-created"

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    [ -f "$TMUX_FAKE_SESSION_CREATED" ]
    ;;
  new-session)
    touch "$TMUX_FAKE_SESSION_CREATED"
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  set-option|set-window-option|select-pane)
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_TEAM"
    elif [ "$4" = '@xmux-display-name' ]; then
      printf 'XMux/dev\\n'
    fi
    ;;
  attach-session)
    printf 'attach-session should not run in non-TTY mode\\n' >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["-n", "dev"],
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_CREATED": str(session_created),
            "TMUX_FAKE_TEAM": "XMux-dev",
        },
        cwd=project,
    )

    assert result.returncode == 0, result.stderr
    fields = {}
    for token in result.stdout.strip().split():
        if ":" not in token:
            continue
        key, value = token.split(":", 1)
        fields[key] = value

    assert fields["name"] == "XMux/dev"
    assert fields["team"].startswith("XMux-dev-")
    assert fields["session"].startswith("xmux-XMux-dev-")
    team_hash = fields["team"][len("XMux-dev-") :]
    session_hash = fields["session"][len("xmux-XMux-dev-") :]
    assert len(team_hash) == 6
    assert len(session_hash) == 6
    assert team_hash == session_hash

    team_config = json.loads(
        (
            state_dir
            / "teams"
            / fields["team"]
            / "team.json"
        ).read_text(encoding="utf-8")
    )
    assert team_config["display_name"] == "XMux/dev"
    assert team_config["lead"]["display_name"] == "XMux/dev"

    log_lines = log_path.read_text(encoding="utf-8").splitlines()
    new_session = next(line for line in log_lines if line.startswith("new-session "))
    assert "-s xmux-XMux-dev-" in new_session
    assert "-s dev" not in new_session
    assert (
        f"set-option -t {fields['session']} @xmux-display-name XMux/dev" in log_lines
    )
    assert "set-option -p -t %1 @xmux-display-name XMux/dev" in log_lines


def _resolve_scoped_name_fields(project, state_dir, raw_name):
    result = run_zsh(
        f'print -r -- "$(_xmux_resolve_name_fields {raw_name})"',
        {
            "XMUX_PROJECT_DIR": str(project),
            "XMUX_STATE_DIR": str(state_dir),
        },
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip().split("\t")


def test_xmux_start_rejects_existing_active_display_name_when_detached(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    exit 0
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_OWNER_TEAM"
    elif [ "$4" = '@xmux-display-name' ]; then
      printf '%s\\n' "$TMUX_FAKE_DISPLAY_NAME"
    fi
    ;;
  list-sessions)
    printf '%s\\t%s\\n' "$TMUX_FAKE_SESSION_NAME" "$TMUX_FAKE_SESSION_ATTACHED"
    ;;
  list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["-n", "dev"],
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_OWNER_TEAM": team_name,
            "TMUX_FAKE_DISPLAY_NAME": display_name,
            "TMUX_FAKE_SESSION_NAME": session_name,
            "TMUX_FAKE_SESSION_ATTACHED": "0",
        },
        cwd=project,
    )

    assert result.returncode == 1
    assert f"error: XMux name '{display_name}' is already active." in result.stderr
    assert (
        f"Use 'xmux attach {display_name}' to reconnect, or 'xmux sessions' to inspect active runtimes."
        in result.stderr
    )
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_start_rejects_existing_active_display_name_when_already_attached(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    exit 0
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_OWNER_TEAM"
    elif [ "$4" = '@xmux-display-name' ]; then
      printf '%s\\n' "$TMUX_FAKE_DISPLAY_NAME"
    fi
    ;;
  list-sessions)
    printf '%s\\t%s\\n' "$TMUX_FAKE_SESSION_NAME" "$TMUX_FAKE_SESSION_ATTACHED"
    ;;
  list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["-n", "dev"],
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_OWNER_TEAM": team_name,
            "TMUX_FAKE_DISPLAY_NAME": display_name,
            "TMUX_FAKE_SESSION_NAME": session_name,
            "TMUX_FAKE_SESSION_ATTACHED": "1",
        },
        cwd=project,
    )

    assert result.returncode == 1
    assert (
        f"error: XMux name '{display_name}' is already attached by another terminal."
        in result.stderr
    )
    assert "Multiple terminals cannot attach to the same XMux name." in result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_inside_tmux_start_rejects_existing_active_display_name_for_scoped_name(
    tmp_path,
):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )

    team_dir = state_dir / "teams" / team_name
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": team_name,
                "display_name": display_name,
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": session_name,
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nprintf 'codex-ran\\n'\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  display-message)
    if [ "$1" = "-p" ] && [ "$2" = "#S" ]; then
      printf '%s\\n' "$TMUX_FAKE_CURRENT_SESSION"
      exit 0
    fi
    exit 1
    ;;
  has-session)
    if [ "$2" = "$TMUX_FAKE_CURRENT_SESSION" ]; then
      exit 0
    fi
    exit 1
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_OWNER_TEAM"
      exit 0
    fi
    if [ "$4" = '@xmux-display-name' ]; then
      printf '%s\\n' "$TMUX_FAKE_DISPLAY_NAME"
      exit 0
    fi
    ;;
  list-sessions)
    if [ "$1" = "-F" ] && [ "$2" = "#S" ]; then
      printf '%s\\n' "$TMUX_FAKE_CURRENT_SESSION"
    else
      printf '%s\\t%s\\n' "$TMUX_FAKE_CURRENT_SESSION" "$TMUX_FAKE_SESSION_ATTACHED"
    fi
    ;;
  list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        """
_xmux_lead_stdio_is_tty() {
  return 0
}
_xmux_start -n dev --keep-team-on-lead-exit || return $?
print -r -- "after-start"
""",
        {
            "XMUX_PROJECT_DIR": str(project),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": "fake-tmux-env",
            "TMUX_PANE": "%7",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_CURRENT_SESSION": session_name,
            "TMUX_FAKE_OWNER_TEAM": team_name,
            "TMUX_FAKE_DISPLAY_NAME": display_name,
            "TMUX_FAKE_SESSION_ATTACHED": "1",
        },
    )

    assert result.returncode == 1
    assert (
        f"error: XMux name '{display_name}' is already attached by another terminal."
        in result.stderr
    )
    assert "Multiple terminals cannot attach to the same XMux name." in result.stderr
    assert "codex-ran" not in result.stdout
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("set-option ") for line in lines)
    assert not any(line.startswith("set-window-option ") for line in lines)
    assert not any(line.startswith("select-pane ") for line in lines)
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_inside_tmux_start_rejects_existing_same_team_display_name_before_state_adoption(
    tmp_path,
):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )
    current_session = "manual-current"

    team_dir = state_dir / "teams" / team_name
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": team_name,
                "display_name": display_name,
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": current_session,
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nprintf 'codex-ran\\n'\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  display-message)
    if [ "$1" = "-p" ] && [ "$2" = "#S" ]; then
      printf '%s\\n' "$TMUX_FAKE_CURRENT_SESSION"
      exit 0
    fi
    exit 1
    ;;
  has-session)
    if [ "$2" = "$TMUX_FAKE_CURRENT_SESSION" ]; then
      exit 0
    fi
    if [ "$2" = "$TMUX_FAKE_RESOLVED_SESSION" ]; then
      exit 1
    fi
    exit 1
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_OWNER_TEAM"
      exit 0
    fi
    if [ "$4" = '@xmux-display-name' ]; then
      printf '%s\\n' "$TMUX_FAKE_DISPLAY_NAME"
      exit 0
    fi
    ;;
  list-sessions)
    if [ "$1" = "-F" ] && [ "$2" = "#S" ]; then
      printf '%s\\n' "$TMUX_FAKE_CURRENT_SESSION"
    else
      printf '%s\\t%s\\n' "$TMUX_FAKE_CURRENT_SESSION" "$TMUX_FAKE_SESSION_ATTACHED"
    fi
    ;;
  list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        """
_xmux_lead_stdio_is_tty() {
  return 0
}
_xmux_start -n dev --keep-team-on-lead-exit || return $?
print -r -- "after-start"
""",
        {
            "XMUX_PROJECT_DIR": str(project),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": "fake-tmux-env",
            "TMUX_PANE": "%7",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_CURRENT_SESSION": current_session,
            "TMUX_FAKE_OWNER_TEAM": team_name,
            "TMUX_FAKE_DISPLAY_NAME": display_name,
            "TMUX_FAKE_RESOLVED_SESSION": session_name,
            "TMUX_FAKE_SESSION_ATTACHED": "1",
        },
    )

    assert result.returncode == 1
    assert (
        f"error: XMux name '{display_name}' is already attached by another terminal."
        in result.stderr
    )
    assert "Multiple terminals cannot attach to the same XMux name." in result.stderr
    assert "codex-ran" not in result.stdout
    assert "after-start" not in result.stdout
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("set-option ") for line in lines)
    assert not any(line.startswith("set-window-option ") for line in lines)
    assert not any(line.startswith("select-pane ") for line in lines)
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_start_rejects_existing_active_display_name_when_owned_by_different_team(
    tmp_path,
):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    display_name, owner_team, owner_session = _resolve_scoped_name_fields(
        project, state_dir, "'a b'"
    )
    other_display_name, _, other_session = _resolve_scoped_name_fields(
        project, state_dir, "a_b"
    )
    assert display_name == other_display_name

    owner_dir = state_dir / "teams" / owner_team
    owner_dir.mkdir(parents=True)
    (owner_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": owner_team,
                "display_name": display_name,
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": owner_session,
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    if [ "$2" = "$TMUX_FAKE_OWNER_SESSION" ]; then
      exit 0
    fi
    if [ "$2" = "$TMUX_FAKE_OTHER_SESSION" ]; then
      exit 1
    fi
    exit 1
    ;;
  list-sessions|show-option|list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["-n", "a_b"],
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_OWNER_SESSION": owner_session,
            "TMUX_FAKE_OTHER_SESSION": other_session,
        },
        cwd=project,
    )

    assert result.returncode == 1
    assert (
        f"error: XMux name '{display_name}' is already active for team '{owner_team}'."
        in result.stderr
    )
    if log_path.exists():
        lines = log_path.read_text(encoding="utf-8").splitlines()
        assert not any(line.startswith("new-session ") for line in lines)
        assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_start_rejects_unowned_internal_session_for_scoped_name(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    exit 0
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_OWNER_TEAM"
    fi
    ;;
  list-sessions)
    printf '%s\\t%s\\n' "$TMUX_FAKE_SESSION_NAME" "$TMUX_FAKE_SESSION_ATTACHED"
    ;;
  list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["-n", "dev"],
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_OWNER_TEAM": "other-team",
            "TMUX_FAKE_SESSION_NAME": session_name,
            "TMUX_FAKE_SESSION_ATTACHED": "0",
        },
        cwd=project,
    )

    assert result.returncode == 1
    assert (
        f"error: internal tmux session for XMux name '{display_name}' already exists but is not owned by this XMux runtime."
        in result.stderr
    )
    assert (
        "Inspect raw tmux sessions with 'tmux ls' and choose another XMux name."
        in result.stderr
    )
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)
    assert not any(line.startswith("list-panes ") for line in lines)
    assert not any(line.startswith("set-option ") for line in lines)
    assert not (state_dir / "teams" / team_name).exists()


def test_xmux_attach_display_name_resolves_internal_session_when_detached(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    team_name = "XMux-dev-abc123"
    session_name = "xmux-XMux-dev-abc123"

    team_dir = state_dir / "teams" / team_name
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": team_name,
                "display_name": "XMux/dev",
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": session_name,
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    if [ "$2" = "$TMUX_FAKE_SESSION_NAME" ]; then
      exit 0
    fi
    exit 1
    ;;
  list-sessions)
    printf '%s\\t%s\\n' "$TMUX_FAKE_SESSION_NAME" "$TMUX_FAKE_SESSION_ATTACHED"
    ;;
  attach-session)
    exit 0
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux attach XMux/dev",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_NAME": session_name,
            "TMUX_FAKE_SESSION_ATTACHED": "0",
            "XMUX_TERMINAL_THEME": "0",
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert f"attach-session -t {session_name}" in lines


def test_xmux_attach_display_name_rejects_when_already_attached(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    team_name = "XMux-dev-abc123"
    session_name = "xmux-XMux-dev-abc123"

    team_dir = state_dir / "teams" / team_name
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": team_name,
                "display_name": "XMux/dev",
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": session_name,
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    if [ "$2" = "$TMUX_FAKE_SESSION_NAME" ]; then
      exit 0
    fi
    exit 1
    ;;
  list-sessions)
    printf '%s\\t%s\\n' "$TMUX_FAKE_SESSION_NAME" "$TMUX_FAKE_SESSION_ATTACHED"
    ;;
  attach-session)
    printf 'attach-session should not run when already attached\\n' >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux attach XMux/dev",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_NAME": session_name,
            "TMUX_FAKE_SESSION_ATTACHED": "1",
            "XMUX_TERMINAL_THEME": "0",
        },
    )

    assert result.returncode == 1
    assert (
        "error: XMux name 'XMux/dev' is already attached by another terminal."
        in result.stderr
    )
    assert "Multiple terminals cannot attach to the same XMux name." in result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_attach_display_name_rejects_ambiguous_active_team_matches(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    team_a = "XMux-a_b-aaaaaa"
    team_b = "XMux-a_b-bbbbbb"
    session_a = "xmux-XMux-a_b-aaaaaa"
    session_b = "xmux-XMux-a_b-bbbbbb"

    for team_name, session_name in ((team_a, session_a), (team_b, session_b)):
        team_dir = state_dir / "teams" / team_name
        team_dir.mkdir(parents=True)
        (team_dir / "team.json").write_text(
            json.dumps(
                {
                    "schema": "xmux.team.v1",
                    "name": team_name,
                    "display_name": "XMux/a_b",
                    "status": "active",
                    "lead": {
                        "name": "codex-lead",
                        "provider": "codex",
                        "session": session_name,
                        "pane": "%1",
                    },
                    "members": {},
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    if [ "$2" = "$TMUX_FAKE_SESSION_A" ] || [ "$2" = "$TMUX_FAKE_SESSION_B" ]; then
      exit 0
    fi
    exit 1
    ;;
  list-sessions)
    printf '%s\\t0\\n%s\\t0\\n' "$TMUX_FAKE_SESSION_A" "$TMUX_FAKE_SESSION_B"
    ;;
  attach-session)
    exit 0
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux attach XMux/a_b",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION_A": session_a,
            "TMUX_FAKE_SESSION_B": session_b,
            "XMUX_TERMINAL_THEME": "0",
        },
    )

    assert result.returncode == 1
    assert "error: XMux name 'XMux/a_b' matches multiple active teams:" in result.stderr
    assert f"{team_a}, {team_b}" in result.stderr
    assert "Use 'xmux attach -t <team>' to disambiguate." in result.stderr
    if log_path.exists():
        lines = log_path.read_text(encoding="utf-8").splitlines()
        assert not any(line.startswith("attach-session ") for line in lines)


def test_xmux_attach_display_name_rejects_mixed_state_and_tmux_ambiguity(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    state_team = "XMux-dev-abc123"
    state_session = "xmux-XMux-dev-abc123"
    fallback_team = "XMux-dev-def456"
    fallback_session = "xmux-XMux-dev-def456"

    team_dir = state_dir / "teams" / state_team
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": state_team,
                "display_name": "XMux/dev",
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": state_session,
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    if [ "$2" = "$TMUX_FAKE_STATE_SESSION" ] || [ "$2" = "$TMUX_FAKE_FALLBACK_SESSION" ]; then
      exit 0
    fi
    exit 1
    ;;
  list-sessions)
    if [ "$1" = "-F" ] && [ "$2" = "#S" ]; then
      printf '%s\\n%s\\n' "$TMUX_FAKE_STATE_SESSION" "$TMUX_FAKE_FALLBACK_SESSION"
    else
      printf '%s\\t0\\n%s\\t0\\n' "$TMUX_FAKE_STATE_SESSION" "$TMUX_FAKE_FALLBACK_SESSION"
    fi
    ;;
  show-option)
    if [ "$4" = '@xmux-display-name' ]; then
      if [ "$3" = "$TMUX_FAKE_STATE_SESSION" ] || [ "$3" = "$TMUX_FAKE_FALLBACK_SESSION" ]; then
        printf 'XMux/dev\\n'
      fi
    elif [ "$4" = '@xmux-team' ]; then
      if [ "$3" = "$TMUX_FAKE_STATE_SESSION" ]; then
        printf '%s\\n' "$TMUX_FAKE_STATE_TEAM"
      elif [ "$3" = "$TMUX_FAKE_FALLBACK_SESSION" ]; then
        printf '%s\\n' "$TMUX_FAKE_FALLBACK_TEAM"
      fi
    fi
    ;;
  list-panes|set-option|set-window-option|select-pane)
    ;;
  attach-session|new-session)
    printf '%s should not run when display name is ambiguous\\n' "$cmd" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    shared_env = {
        "XMUX_STATE_DIR": str(state_dir),
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "TMUX": None,
        "TMUX_PANE": None,
        "TMUX_FAKE_LOG": str(log_path),
        "TMUX_FAKE_STATE_TEAM": state_team,
        "TMUX_FAKE_STATE_SESSION": state_session,
        "TMUX_FAKE_FALLBACK_TEAM": fallback_team,
        "TMUX_FAKE_FALLBACK_SESSION": fallback_session,
        "XMUX_TERMINAL_THEME": "0",
    }

    attach_result = run_zsh("xmux attach XMux/dev", shared_env)

    assert attach_result.returncode == 1
    assert "error: XMux name 'XMux/dev' matches multiple active teams:" in attach_result.stderr
    assert state_team in attach_result.stderr
    assert fallback_team in attach_result.stderr
    assert "Use 'xmux attach -t <team>' to disambiguate." in attach_result.stderr

    start_result = run_xmux_bin(["-n", "dev"], shared_env, cwd=project)

    assert start_result.returncode == 1
    assert "error: XMux name 'XMux/dev' matches multiple active teams:" in start_result.stderr
    assert state_team in start_result.stderr
    assert fallback_team in start_result.stderr
    assert "Use 'xmux attach -t <team>' to disambiguate." in start_result.stderr

    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("attach-session ") for line in lines)
    assert not any(line.startswith("new-session ") for line in lines)


def test_xmux_team_for_display_name_fallback_skips_inactive_team_state(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    team_dir = state_dir / "teams" / "demo"
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": "demo",
                "display_name": "XMux/dev",
                "status": "shutdown",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": "demo-session",
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
cmd="$1"
shift
case "$cmd" in
  list-sessions)
    printf 'demo-session\\n'
    ;;
  show-option)
    if [ "$4" = '@xmux-display-name' ]; then
      printf 'XMux/dev\\n'
    elif [ "$4" = '@xmux-team' ]; then
      printf 'demo\\n'
    fi
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        """
team="$(_xmux_team_for_display_name XMux/dev)"
rc="$?"
print -r -- "$rc"$'\\t'"$team"
""",
        {
            "XMUX_PROJECT_DIR": str(project),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        },
    )

    assert result.returncode == 0, result.stderr
    rc, team = result.stdout.rstrip("\n").split("\t", 1)
    assert rc == "1"
    assert team == ""


def test_xmux_hash_uses_raw_short_name_before_slugging(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()

    result = run_zsh(
        """
first="$(_xmux_resolve_name_fields 'a b')"
second="$(_xmux_resolve_name_fields 'a_b')"
print -r -- "$first"
print -r -- "$second"
""",
        {
            "XMUX_PROJECT_DIR": str(project),
            "XMUX_STATE_DIR": str(project / ".codex" / "xmux"),
        },
    )

    assert result.returncode == 0, result.stderr
    first_display, first_team, first_session = result.stdout.splitlines()[0].split("\t")
    second_display, second_team, second_session = result.stdout.splitlines()[1].split(
        "\t"
    )

    assert first_display == "XMux/a_b"
    assert second_display == "XMux/a_b"
    assert first_team.startswith("XMux-a_b-")
    assert second_team.startswith("XMux-a_b-")
    assert first_session.startswith("xmux-XMux-a_b-")
    assert second_session.startswith("xmux-XMux-a_b-")
    assert first_team != second_team
    assert first_session != second_session


def test_xmux_attach_session_wraps_attach_with_terminal_theme(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
case "$1" in
  attach-session)
    exit 0
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        '_xmux_attach_session demo-session; print -r -- "after-attach"',
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "XMUX_TERMINAL_THEME_FORCE": "1",
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    assert log_path.read_text(encoding="utf-8").splitlines() == [
        "attach-session -t demo-session"
    ]
    assert result.stdout.startswith("\033]10;#F5F7FA\033\\")
    assert "\033]11;#0E0F12\033\\" in result.stdout
    assert "\033]4;2;#10A37F\033\\" in result.stdout
    assert "\033]105\033\\after-attach\n" in result.stdout


def test_xmux_attach_session_respects_terminal_theme_disable(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
case "$1" in
  attach-session)
    exit 0
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        '_xmux_attach_session demo-session; print -r -- "after-attach"',
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "XMUX_TERMINAL_THEME": "0",
            "XMUX_TERMINAL_THEME_FORCE": "1",
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    assert log_path.read_text(encoding="utf-8").splitlines() == [
        "attach-session -t demo-session"
    ]
    assert result.stdout == "after-attach\n"


def test_xmux_inside_tmux_lead_run_wraps_codex_with_terminal_theme(tmp_path):
    state_dir = tmp_path / ".xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nprintf 'codex-ran\\n'\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
case "$1" in
  display-message)
    if [ "$2" = "-p" ] && [ "$3" = "#S" ]; then
      printf 'demo-session\\n'
    fi
    ;;
  set-option|set-window-option|select-pane)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        """
_xmux_lead_stdio_is_tty() {
  return 0
}
_xmux_start -T demo --keep-team-on-lead-exit || return $?
print -r -- "after-lead"
""",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "XMUX_TERMINAL_THEME_FORCE": "1",
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": "fake-tmux-env",
            "TMUX_PANE": "%1",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    assert log_path.read_text(encoding="utf-8").splitlines()[0] == "display-message -p #S"
    assert result.stdout.startswith("\033]10;#F5F7FA\033\\")
    assert "codex-ran\n" in result.stdout
    assert "\033]105\033\\after-lead\n" in result.stdout


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

    result = run_zsh("xmux bridgeStatus -t demo", {"XMUX_STATE_DIR": str(state_dir)})

    assert result.returncode == 0, result.stderr
    assert "TEAM" in result.stdout
    assert "worker-a" in result.stdout
    assert "gemini" in result.stdout
    assert "BRIDGE" in result.stdout


def test_xmux_send_pane_injects_prompt_to_resolved_pane(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux sendPane demo:worker-a 'check the failing test' --clear",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert any("load-buffer -b xmux-send-pane-" in line for line in lines)
    assert "send-keys -t %2 C-u" in lines
    assert any("paste-buffer -p -b xmux-send-pane-" in line and "-t %2" in line for line in lines)
    assert "send-keys -t %2 Enter" in lines


def write_fake_tmux(bin_dir):
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-panes)
    printf '%s\\n' "$TMUX_FAKE_PANES"
    ;;
  has-session)
    exit 0
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_TEAM"
    fi
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
    case "$fmt" in
      *@xmux-team*@xmux-agent*)
        printf '%s\\t%s\\n' "${TMUX_FAKE_TAG_TEAM:-$TMUX_FAKE_TEAM}" "${TMUX_FAKE_TAG_AGENT:-worker-a}"
        ;;
      '#{pane_id}')
        printf '%s\\n' "$target"
        ;;
      '#{session_name}')
        printf '%s\\n' "${TMUX_FAKE_SESSION:-demo}"
        ;;
      '#{@xmux-lead}')
        printf '\\n'
        ;;
      *)
        [ -n "$target" ] && printf '%s\\t%s\\n' "${TMUX_FAKE_TAG_TEAM:-$TMUX_FAKE_TEAM}" "${TMUX_FAKE_TAG_AGENT:-worker-a}"
        ;;
    esac
    ;;
  run-shell)
    all="$*"
    case "$all" in
      *xmux-bridge.zsh*)
        [ -n "$TMUX_FAKE_BRIDGE_PID_FILE" ] && printf '%s\\n' "$TMUX_FAKE_LIVE_PID" > "$TMUX_FAKE_BRIDGE_PID_FILE"
        ;;
      *bridge-mcp-server.js*)
        [ -n "$TMUX_FAKE_HTTP_PID_FILE" ] && printf '%s\\n' "$TMUX_FAKE_LIVE_PID" > "$TMUX_FAKE_HTTP_PID_FILE"
        ;;
    esac
    ;;
  select-pane|kill-pane)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)
    return tmux


def test_xmux_applies_codex_border_and_provider_name_color(tmp_path):
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "_xmux_apply_pane_brand_style %2 claude-worker claude",
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert "select-pane -t %2 -T claude-worker" in lines
    assert "set-option -p -t %2 pane-border-style fg=#10A37F" in lines
    assert "set-option -p -t %2 pane-active-border-style fg=#10A37F,bold" in lines
    assert (
        "set-option -p -t %2 pane-border-format "
        "#[fg=#D97757,bold] #{@agent_name} #[default]"
    ) in lines


def test_xmux_applies_codex_session_status_uses_display_name_layout(tmp_path):
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "_xmux_apply_session_brand_status demo-session XMux-test-dev-a9a430 XMux/test-dev",
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert "set-option -t demo-session status on" in lines
    assert "set-option -t demo-session status-position bottom" in lines
    assert "set-option -t demo-session status-style bg=#0E0F12,fg=#F5F7FA" in lines
    assert (
        "set-option -t demo-session status-left "
        "#[bg=#10A37F,fg=#0E0F12,bold] XMux "
        "#[bg=#252A31,fg=#F5F7FA,nobold] XMux/test-dev "
        "#[bg=#17191D,fg=#F3F4F6] #W "
    ) in lines
    assert (
        "set-option -t demo-session status-right "
        "#[bg=#17191D,fg=#F3F4F6] xmux 1.0.40 #[bg=#252A31,fg=#F5F7FA] %H:%M "
    ) in lines
    assert not any(" | " in line and "status-left" in line for line in lines)
    assert not any(" | " in line and "status-right" in line for line in lines)
    assert not any("XMux-test-dev-a9a430" in line and "status-left" in line for line in lines)
    assert not any("#S" in line and "status-right" in line for line in lines)
    assert not any("codex-lead" in line and "status-right" in line for line in lines)
    window_status_format_line = next(
        line for line in lines if line.startswith("set-option -t demo-session window-status-format")
    )
    window_status_current_line = next(
        line for line in lines if line.startswith("set-option -t demo-session window-status-current-format")
    )
    window_status_separator_line = next(
        line for line in lines if line.startswith("set-option -t demo-session window-status-separator")
    )
    assert window_status_format_line in (
        "set-option -t demo-session window-status-format",
        "set-option -t demo-session window-status-format ",
    )
    assert window_status_current_line in (
        "set-option -t demo-session window-status-current-format",
        "set-option -t demo-session window-status-current-format ",
    )
    assert window_status_separator_line in (
        "set-option -t demo-session window-status-separator",
        "set-option -t demo-session window-status-separator ",
    )
    assert "set-window-option -t demo-session mode-style bg=#10A37F,fg=#0E0F12" in lines


def test_xmux_applies_codex_session_status_sanitizes_control_chars_and_escapes_hash(tmp_path):
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "_xmux_apply_session_brand_status demo-session XMux-test-dev-a9a430 $'XMux/\\e#bad\\ax'",
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    status_left_line = next(
        line for line in lines if line.startswith("set-option -t demo-session status-left ")
    )
    status_left_value = status_left_line.split(" status-left ", 1)[1]
    assert "XMux/ ##bad x" in status_left_value
    assert "\x1b" not in status_left_value
    assert "\x07" not in status_left_value
    assert "#W" in status_left_value


def test_xmux_session_status_style_can_be_disabled(tmp_path):
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "_xmux_apply_session_brand_status demo-session demo",
        {
            "XMUX_STATE_DIR": str(tmp_path / ".xmux"),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "XMUX_STATUS_STYLE": "0",
        },
    )

    assert result.returncode == 0, result.stderr
    assert not log_path.exists()


def test_xmux_records_lead_pane_with_codex_brand_style(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))

    result = run_zsh(
        "_xmux_record_lead_pane XMux-test-dev-a9a430 %1 xmux-XMux-test-dev-a9a430 XMux/test-dev",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert "select-pane -t %1 -T codex-lead" in lines
    assert "set-option -p -t %1 pane-border-style fg=#10A37F" in lines
    assert (
        "set-option -p -t %1 pane-border-format "
        "#[fg=#10A37F,bold] #{@agent_name} #[default]"
    ) in lines
    status_left_line = next(
        line for line in lines if line.startswith("set-option -t xmux-XMux-test-dev-a9a430 status-left ")
    )
    status_right_line = next(
        line for line in lines if line.startswith("set-option -t xmux-XMux-test-dev-a9a430 status-right ")
    )
    status_left_value = status_left_line.split(" status-left ", 1)[1]
    status_right_value = status_right_line.split(" status-right ", 1)[1]
    assert "XMux/test-dev" in status_left_line
    assert "#W" in status_left_line
    assert "XMux-test-dev-a9a430" not in status_left_value
    assert "xmux 1.0.40" in status_right_line
    assert "%H:%M" in status_right_line
    assert "#S" not in status_right_value
    status_format_line = next(
        line for line in lines if line.startswith("set-option -t xmux-XMux-test-dev-a9a430 window-status-format")
    )
    status_current_line = next(
        line
        for line in lines
        if line.startswith("set-option -t xmux-XMux-test-dev-a9a430 window-status-current-format")
    )
    status_separator_line = next(
        line for line in lines if line.startswith("set-option -t xmux-XMux-test-dev-a9a430 window-status-separator")
    )
    assert status_format_line in (
        "set-option -t xmux-XMux-test-dev-a9a430 window-status-format",
        "set-option -t xmux-XMux-test-dev-a9a430 window-status-format ",
    )
    assert status_current_line in (
        "set-option -t xmux-XMux-test-dev-a9a430 window-status-current-format",
        "set-option -t xmux-XMux-test-dev-a9a430 window-status-current-format ",
    )
    assert status_separator_line in (
        "set-option -t xmux-XMux-test-dev-a9a430 window-status-separator",
        "set-option -t xmux-XMux-test-dev-a9a430 window-status-separator ",
    )


def test_xmux_sessions_displays_xmux_name_not_internal_session(tmp_path):
    state_dir = tmp_path / ".xmux"
    team = "XMux-dev-abc123"
    internal_session = "xmux-XMux-dev-abc123"
    display_name = "XMux/dev"
    team_dir = state_dir / "teams" / team
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": team,
                "display_name": display_name,
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": internal_session,
                    "pane": "%1",
                },
                "members": {},
            }
        )
        + "\n",
        encoding="utf-8",
    )

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    tmux = bin_dir / "tmux"
    tmux.write_text(
        f"""#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-sessions)
    printf '{internal_session}\\t0\\t1\\n'
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '{team}\\n'
    elif [ "$4" = '@xmux-display-name' ]; then
      printf '{display_name}\\n'
    fi
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  display-message)
    printf 'zsh\\n'
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    env = {
        "XMUX_STATE_DIR": str(state_dir),
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "TMUX_FAKE_LOG": str(log_path),
    }
    result = run_zsh("xmux sessions", env)
    filtered_internal = run_zsh("xmux sessions --filter dev", env)
    filtered_display = run_zsh("xmux sessions --filter 'XMux/dev'", env)
    filtered_internal_full = run_zsh(f"xmux sessions --filter '{internal_session}'", env)
    filtered_literal_star = run_zsh("xmux sessions --filter '*'", env)
    filtered_literal_class = run_zsh("xmux sessions --filter '[abc]'", env)
    filtered_malformed = run_zsh("xmux sessions --filter '['", env)

    assert result.returncode == 0, result.stderr
    assert display_name in result.stdout
    assert internal_session not in result.stdout

    assert filtered_internal.returncode == 0, filtered_internal.stderr
    assert display_name in filtered_internal.stdout
    assert internal_session not in filtered_internal.stdout

    assert filtered_display.returncode == 0, filtered_display.stderr
    assert display_name in filtered_display.stdout
    assert internal_session not in filtered_display.stdout

    assert filtered_internal_full.returncode == 0, filtered_internal_full.stderr
    assert display_name in filtered_internal_full.stdout
    assert internal_session not in filtered_internal_full.stdout

    assert filtered_literal_star.returncode == 0, filtered_literal_star.stderr
    assert "bad pattern" not in filtered_literal_star.stderr.lower()
    assert display_name not in filtered_literal_star.stdout
    assert internal_session not in filtered_literal_star.stdout
    assert "(no XMux sessions match" in filtered_literal_star.stdout

    assert filtered_literal_class.returncode == 0, filtered_literal_class.stderr
    assert "bad pattern" not in filtered_literal_class.stderr.lower()
    assert display_name not in filtered_literal_class.stdout
    assert internal_session not in filtered_literal_class.stdout
    assert "(no XMux sessions match" in filtered_literal_class.stdout

    assert filtered_malformed.returncode == 0, filtered_malformed.stderr
    assert "bad pattern" not in filtered_malformed.stderr.lower()
    assert display_name not in filtered_malformed.stdout
    assert "(no XMux sessions match" in filtered_malformed.stdout


def test_xmux_sessions_hides_stale_shutdown_team_option(tmp_path):
    state_dir = tmp_path / ".xmux"
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
  list-sessions)
    printf 'demo-session\\t0\\t1\\n'
    ;;
  show-option)
    printf 'demo\\n'
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  display-message)
    printf 'zsh\\n'
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    env = {
        "XMUX_STATE_DIR": str(state_dir),
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "TMUX_FAKE_LOG": str(log_path),
    }
    active = run_zsh("xmux sessions", env)
    all_sessions = run_zsh("xmux sessions --all", env)

    assert active.returncode == 0, active.stderr
    assert "demo-session" not in active.stdout
    assert "no XMux sessions match" in active.stdout
    assert all_sessions.returncode == 0, all_sessions.stderr
    assert "demo-session" in all_sessions.stdout
    rows = [
        line.split()
        for line in all_sessions.stdout.splitlines()
        if line.startswith("demo-session")
    ]
    assert rows and rows[0][1] == "-"


def test_xmux_shutdown_cleanup_unsets_display_name_metadata(tmp_path):
    state_dir = tmp_path / ".xmux"
    log_path = tmp_path / "tmux.log"
    team_dir = state_dir / "teams" / "demo"
    team_dir.mkdir(parents=True)
    (team_dir / "team.json").write_text(
        json.dumps(
            {
                "schema": "xmux.team.v1",
                "name": "demo",
                "display_name": "XMux/dev",
                "status": "active",
                "lead": {
                    "name": "codex-lead",
                    "provider": "codex",
                    "session": "demo-session",
                    "pane": "%1",
                },
                "members": {},
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    [ "$2" = "demo-session" ]
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf 'demo\\n'
    fi
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
    if [ "$target" = "%1" ] && [ "$fmt" = '#{@xmux-team}\t#{@xmux-lead}' ]; then
      printf 'demo\\t1\\n'
    fi
    ;;
  set-option)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "_xmux_clear_team_tmux_metadata demo",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert "set-option -u -t demo-session @xmux-team" in lines
    assert "set-option -u -t demo-session @xmux-display-name" in lines
    assert "set-option -p -u -t %1 @xmux-agent" in lines
    assert "set-option -p -u -t %1 @xmux-team" in lines
    assert "set-option -p -u -t %1 @xmux-display-name" in lines
    assert "set-option -p -u -t %1 @xmux-lead" in lines


def test_xmux_team_status_uses_unknown_when_tmux_socket_unavailable(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux teamStatus -t demo",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "worker-a" in result.stdout
    assert "unknown" in result.stdout
    assert "dead" not in result.stdout


def test_xmux_shutdown_archives_team_and_preserves_history(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")
    xmux_mailbox.enqueue_request(
        "demo",
        "worker-a",
        from_name="codex-lead",
        message="preserve this request",
        request_id="req-preserve-001",
    )

    team_dir = state_dir / "teams" / "demo"
    registry_path = state_dir / "active-teams" / "demo.json"
    registry_path.parent.mkdir(parents=True)
    registry_path.write_text(
        json.dumps(
            {
                "schema": "xmux.active_team.v1",
                "team": "demo",
                "project_dir": str(ROOT),
                "state_dir": str(state_dir),
                "team_dir": str(team_dir),
                "status": "active",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    (team_dir / ".worker-a-bridge.pid").write_text(
        f"{os.getpid()}\n", encoding="utf-8"
    )
    (team_dir / ".worker-a-mcp-http.pid").write_text("not-a-pid\n", encoding="utf-8")

    result = run_zsh(
        "xmux shutdown -t demo --timeout 0 --reason manual-shutdown",
        {"XMUX_STATE_DIR": str(state_dir)},
    )

    assert result.returncode == 0, result.stderr
    assert not team_dir.exists()
    assert not registry_path.exists()
    archives = sorted((state_dir / "archive").glob("*-demo"))
    assert len(archives) == 1
    archive = archives[0]
    archive_meta = json.loads((archive / "archive.json").read_text(encoding="utf-8"))
    assert archive_meta["team"] == "demo"
    assert archive_meta["reason"] == "manual-shutdown"
    assert archive_meta["status"] == "archived"
    team_cfg = json.loads((archive / "team.json").read_text(encoding="utf-8"))
    assert team_cfg["status"] == "archived"
    assert team_cfg["members"]["worker-a"]["active"] is False
    assert (archive / "inboxes" / "codex-lead.json").is_file()
    assert (archive / "inboxes" / "worker-a.json").is_file()
    assert (archive / "requests" / "req-preserve-001.json").is_file()
    assert not (archive / ".worker-a-bridge.pid").exists()
    assert not (archive / ".worker-a-mcp-http.pid").exists()
    events = (archive / "events.jsonl").read_text(encoding="utf-8")
    assert "team.shutdown_started" in events
    assert "team.shutdown_completed" in events
    assert "team.archived" in events


def test_xmux_shutdown_does_not_kill_mismatched_stale_pane(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

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
    printf '%%2\\n'
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
    if [ "$target" = '%2' ] && [ "$fmt" = '#{@xmux-team}\t#{@xmux-agent}' ]; then
      printf 'other-team\\tother-agent\\n'
    fi
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux shutdown -t demo --timeout 0 --reason manual-shutdown",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert "send-keys -t %2 C-c" not in lines
    assert "send-keys -t %2 C-d" not in lines
    assert "kill-pane -t %2" not in lines
    assert not (state_dir / "teams" / "demo").exists()
    assert sorted((state_dir / "archive").glob("*-demo"))


def test_xmux_shutdown_does_not_archive_when_teammate_pane_remains_live(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

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
    printf '%%2\\n'
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
    if [ "$target" = '%2' ] && [ "$fmt" = '#{@xmux-team}\t#{@xmux-agent}' ]; then
      printf 'demo\\tworker-a\\n'
    fi
    ;;
  send-keys)
    ;;
  kill-pane)
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux shutdown -t demo --timeout 0 --reason manual-shutdown",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode != 0
    assert "failed agents: worker-a" in result.stderr
    team_dir = state_dir / "teams" / "demo"
    assert team_dir.exists()
    assert not (state_dir / "archive").exists()
    team_cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    assert team_cfg["status"] == "degraded"
    assert team_cfg["shutdown"]["failed_agents"] == ["worker-a"]
    assert team_cfg["members"]["worker-a"]["active"] is True
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert lines.count("send-keys -t %2 C-c") == 2
    assert "send-keys -t %2 C-d" not in lines
    assert "kill-pane -t %2" in lines


def test_xmux_shutdown_does_not_kill_unverified_http_mcp_pid(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot")

    proc = subprocess.Popen(["sleep", "60"])
    try:
        team_dir = state_dir / "teams" / "demo"
        pid_file = team_dir / ".copilot-worker-mcp-http.pid"
        metadata_file = team_dir / ".copilot-worker-mcp-http.json"
        pid_file.write_text(f"{proc.pid}\n", encoding="utf-8")

        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        ps = bin_dir / "ps"
        ps.write_text(
            """#!/bin/sh
if [ "$1" = "-p" ] && [ "$2" = "$XMUX_FAKE_HTTP_PID" ]; then
  printf 'node /other/xmux/bridge-mcp-server.js --http 43210\\n'
  exit 0
fi
exec /bin/ps "$@"
""",
            encoding="utf-8",
        )
        ps.chmod(0o755)

        result = run_zsh(
            "xmux shutdown -t demo --timeout 0 --reason manual-shutdown",
            {
                "XMUX_STATE_DIR": str(state_dir),
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "XMUX_FAKE_HTTP_PID": str(proc.pid),
            },
        )

        assert result.returncode == 0, result.stderr
        assert "shutdown complete team:demo archived:" in result.stdout
        assert proc.poll() is None
        assert not pid_file.exists()
        assert not metadata_file.exists()
        assert not team_dir.exists()
        archive_dirs = sorted((state_dir / "archive").glob("*-demo"))
        assert len(archive_dirs) == 1
        team_cfg = json.loads(
            (archive_dirs[0] / "team.json").read_text(encoding="utf-8")
        )
        assert team_cfg["status"] == "archived"
        assert team_cfg["members"]["copilot-worker"]["active"] is False
        assert "failed_agents" not in team_cfg["shutdown"]
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def test_xmux_shutdown_no_archive_marks_inactive_and_hides_from_active_listing(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")
    registry_path = state_dir / "active-teams" / "demo.json"
    registry_path.parent.mkdir(parents=True)
    registry_path.write_text(
        json.dumps(
            {
                "schema": "xmux.active_team.v1",
                "team": "demo",
                "project_dir": str(ROOT),
                "state_dir": str(state_dir),
                "team_dir": str(state_dir / "teams" / "demo"),
                "status": "active",
            }
        )
        + "\n",
        encoding="utf-8",
    )

    result = run_zsh(
        "xmux shutdown -t demo --timeout 0 --no-archive --reason manual-shutdown",
        {"XMUX_STATE_DIR": str(state_dir)},
    )

    assert result.returncode == 0, result.stderr
    team_dir = state_dir / "teams" / "demo"
    team_cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    assert team_cfg["status"] == "shutdown"
    assert team_cfg["members"]["worker-a"]["active"] is False
    assert not registry_path.exists()

    active = run_zsh("xmux teammates", {"XMUX_STATE_DIR": str(state_dir)})
    assert active.returncode == 0, active.stderr
    assert "worker-a" not in active.stdout

    explicit = run_zsh("xmux teammates -t demo", {"XMUX_STATE_DIR": str(state_dir)})
    assert explicit.returncode == 0, explicit.stderr
    assert "worker-a" in explicit.stdout
    assert "inactive" in explicit.stdout


def test_xmux_lead_wrapper_shutdown_preserves_codex_exit_status(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 42\n", encoding="utf-8")
    codex.chmod(0o755)

    env = {
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_TEAM": "demo",
        "XMUX_AGENT": "codex-lead",
        "XMUX_TEAM_DIR": str(state_dir / "teams" / "demo"),
        "XMUX_SHUTDOWN_ON_LEAD_EXIT": "1",
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
    }
    result = run_zsh(
        """
_xmux_lead_stdio_is_tty() {
  return 0
}
_xmux_run_codex_lead --fake
""",
        env,
    )

    assert result.returncode == 42
    assert not (state_dir / "teams" / "demo").exists()
    archives = sorted((state_dir / "archive").glob("*-demo"))
    assert len(archives) == 1
    archive_meta = json.loads((archives[0] / "archive.json").read_text(encoding="utf-8"))
    assert archive_meta["reason"] == "lead-exit"


def test_xmux_lead_wrapper_skips_auto_shutdown_without_terminal_stdio(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    codex = bin_dir / "codex"
    codex.write_text(
        "#!/bin/sh\nprintf 'stdin is not a terminal\\n' >&2\nexit 1\n",
        encoding="utf-8",
    )
    codex.chmod(0o755)

    env = {
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_TEAM": "demo",
        "XMUX_AGENT": "codex-lead",
        "XMUX_TEAM_DIR": str(state_dir / "teams" / "demo"),
        "XMUX_SHUTDOWN_ON_LEAD_EXIT": "1",
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
    }
    result = run_zsh("_xmux_run_codex_lead", env)

    assert result.returncode == 1
    assert "stdin is not a terminal" in result.stderr
    assert "skipping automatic shutdown" in result.stderr
    assert (state_dir / "teams" / "demo" / "team.json").is_file()
    assert not (state_dir / "archive").exists()


def test_xmux_lead_wrapper_can_skip_shutdown_on_exit(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 7\n", encoding="utf-8")
    codex.chmod(0o755)

    env = {
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_TEAM": "demo",
        "XMUX_AGENT": "codex-lead",
        "XMUX_TEAM_DIR": str(state_dir / "teams" / "demo"),
        "XMUX_SHUTDOWN_ON_LEAD_EXIT": "0",
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
    }
    result = run_zsh("_xmux_run_codex_lead", env)

    assert result.returncode == 7
    assert (state_dir / "teams" / "demo" / "team.json").is_file()
    assert not (state_dir / "archive").exists()


def assert_xmux_protocol_block(path, template_path, preserved_text):
    text = path.read_text(encoding="utf-8")
    template = template_path.read_text(encoding="utf-8").strip()
    assert preserved_text in text
    assert "<!-- XMUX_PROTOCOL_BEGIN -->" in text
    assert "<!-- XMUX_PROTOCOL_END -->" in text
    assert template in text
    assert "write_to_lead" in text
    assert "request_id" in text


def test_xmux_ensure_restarts_stale_bridge_pid(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    team_dir = state_dir / "teams" / "demo"
    bridge_pid = team_dir / ".worker-a-bridge.pid"
    bridge_pid.write_text("not-a-pid\n", encoding="utf-8")
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux ensure -t demo worker-a --bridge --json",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
            "TMUX_FAKE_TAG_AGENT": "worker-a",
            "TMUX_FAKE_LIVE_PID": str(os.getpid()),
            "TMUX_FAKE_BRIDGE_PID_FILE": str(bridge_pid),
        },
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    target = payload["targets"][0]
    assert payload["ready"] is True
    assert target["bridge"] == {"state": "alive", "pid": os.getpid()}
    assert "removed stale bridge pid" in target["actions"]
    assert "started bridge" in target["actions"]


def test_xmux_ensure_json_resolves_dead_pane_member(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%9")

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux ensure -t demo worker-a --bridge --json",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1",
            "TMUX_FAKE_TEAM": "demo",
        },
    )

    assert result.returncode == 1
    assert "not found" not in result.stderr
    payload = json.loads(result.stdout)
    target = payload["targets"][0]
    assert payload["ready"] is False
    assert target["pane"] == {"id": "%9", "state": "dead"}
    assert "bridge requires live pane" in target["issues"]


def test_xmux_ensure_all_json_is_clean_for_multiple_targets(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "gemini-worker", "gemini", pane="%2")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%3")

    result = run_zsh(
        "xmux ensure -t demo --all --json",
        {"XMUX_STATE_DIR": str(state_dir)},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.lstrip().startswith("{")
    payload = json.loads(result.stdout)
    assert payload["team"] == "demo"
    assert [target["agent"] for target in payload["targets"]] == [
        "copilot-worker",
        "gemini-worker",
    ]
    registry = json.loads(
        (state_dir / "active-teams" / "demo.json").read_text(encoding="utf-8")
    )
    assert registry["team"] == "demo"
    assert registry["state_dir"] == str(state_dir)
    assert registry["lead_pane"] == "%1"


def test_xmux_ensure_repairs_copilot_http_mcp_and_project_prompt(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    project_dir = tmp_path / "project"
    home = tmp_path / "home"
    project_dir.mkdir()
    home.mkdir()
    prompt_path = project_dir / ".github" / "copilot-instructions.md"
    prompt_path.parent.mkdir()
    prompt_path.write_text(
        "Project Copilot rules stay here.\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%2")

    team_dir = state_dir / "teams" / "demo"
    bridge_pid = team_dir / ".copilot-worker-bridge.pid"
    bridge_pid.write_text(f"{os.getpid()}\n", encoding="utf-8")
    bridge_meta = team_dir / ".copilot-worker-bridge.meta"
    bridge_meta.write_text(
        f"team=demo\nagent=copilot-worker\nkind=bridge\npid={os.getpid()}\n",
        encoding="utf-8",
    )
    http_pid = team_dir / ".copilot-worker-mcp-http.pid"
    http_pid.write_text("not-a-pid\n", encoding="utf-8")
    old_url = team_dir / ".copilot-worker-mcp-http.url"
    old_url.write_text("http://127.0.0.1:1/sse\n", encoding="utf-8")

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)
    curl = bin_dir / "curl"
    curl.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    curl.chmod(0o755)

    result = run_zsh(
        "xmux ensure -t demo copilot-worker --ready --json",
        {
            "HOME": str(home),
            "XMUX_PROJECT_DIR": str(project_dir),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
            "TMUX_FAKE_TAG_AGENT": "copilot-worker",
            "TMUX_FAKE_LIVE_PID": str(os.getpid()),
            "TMUX_FAKE_BRIDGE_PID_FILE": str(bridge_pid),
            "TMUX_FAKE_HTTP_PID_FILE": str(http_pid),
        },
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    target = payload["targets"][0]
    assert target["ready"] is True
    assert target["http_mcp"] == {"state": "alive", "pid": os.getpid()}
    assert "removed stale Copilot HTTP MCP pid" in target["actions"]
    assert "started Copilot HTTP MCP" in target["actions"]
    assert "installed XMux Copilot protocol block" in target["actions"]
    assert_xmux_protocol_block(
        prompt_path,
        ROOT / "prompt" / "COPILOT.md",
        "Project Copilot rules stay here.",
    )
    config = json.loads((home / ".copilot" / "mcp-config.json").read_text())
    assert config["mcpServers"]["xmux_bridge"]["url"] == old_url.read_text().strip()


def test_xmux_ensure_installs_gemini_protocol_block_preserving_content(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    project_dir = tmp_path / "project"
    home = tmp_path / "home"
    project_dir.mkdir()
    home.mkdir()
    prompt_path = project_dir / ".gemini" / "GEMINI.md"
    prompt_path.parent.mkdir()
    prompt_path.write_text("Project Gemini rules stay here.\n", encoding="utf-8")
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "gemini-worker", "gemini", pane="%2")

    team_dir = state_dir / "teams" / "demo"
    bridge_pid = team_dir / ".gemini-worker-bridge.pid"
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux ensure -t demo gemini-worker --ready --json",
        {
            "HOME": str(home),
            "XMUX_PROJECT_DIR": str(project_dir),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
            "TMUX_FAKE_TAG_AGENT": "gemini-worker",
            "TMUX_FAKE_LIVE_PID": str(os.getpid()),
            "TMUX_FAKE_BRIDGE_PID_FILE": str(bridge_pid),
        },
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    target = payload["targets"][0]
    assert target["ready"] is True
    assert "installed XMux Gemini protocol block" in target["actions"]
    assert_xmux_protocol_block(
        prompt_path,
        ROOT / "prompt" / "GEMINI.md",
        "Project Gemini rules stay here.",
    )


def test_xmux_ensure_installs_claude_protocol_and_mcp_config(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    project_dir = tmp_path / "project"
    home = tmp_path / "home"
    project_dir.mkdir()
    home.mkdir()
    prompt_path = project_dir / "CLAUDE.md"
    prompt_path.write_text("Project Claude rules stay here.\n", encoding="utf-8")
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "claude-worker", "claude", pane="%2")

    team_dir = state_dir / "teams" / "demo"
    bridge_pid = team_dir / ".claude-worker-bridge.pid"
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux ensure -t demo claude-worker --ready --json",
        {
            "HOME": str(home),
            "XMUX_PROJECT_DIR": str(project_dir),
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
            "TMUX_FAKE_TAG_AGENT": "claude-worker",
            "TMUX_FAKE_LIVE_PID": str(os.getpid()),
            "TMUX_FAKE_BRIDGE_PID_FILE": str(bridge_pid),
        },
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    target = payload["targets"][0]
    assert target["ready"] is True
    assert "installed XMux Claude protocol block" in target["actions"]
    assert "configured Claude MCP bridge" in target["actions"]
    assert_xmux_protocol_block(
        prompt_path,
        ROOT / "prompt" / "CLAUDE.md",
        "Project Claude rules stay here.",
    )
    config = json.loads((home / ".claude.json").read_text(encoding="utf-8"))
    server = config["projects"][str(project_dir)]["mcpServers"]["xmux_bridge"]
    outbox = team_dir / "inboxes" / "codex-lead.json"
    assert server["command"] == "node"
    assert server["args"] == [
        str(ROOT / "bridge-mcp-server.js"),
        "--outbox",
        str(outbox),
        "--agent",
        "claude-worker",
        "--team",
        "demo",
    ]
    assert server["env"]["XMUX_TEAM"] == "demo"
    assert server["env"]["XMUX_STATE_DIR"] == str(state_dir)


def test_xmux_ensure_does_not_start_bridge_for_mismatched_pane_tags(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux ensure -t demo worker-a --bridge --json",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
            "TMUX_FAKE_TAG_TEAM": "other-team",
            "TMUX_FAKE_TAG_AGENT": "other-agent",
        },
    )

    assert result.returncode == 1
    payload = json.loads(result.stdout)
    target = payload["targets"][0]
    assert target["pane"] == {"id": "%2", "state": "stale"}
    assert "pane tag mismatch" in target["issues"]
    assert "run-shell" not in log_path.read_text(encoding="utf-8")


def test_xmux_shutdown_agent_does_not_kill_mismatched_pane_tags(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux shutdown -t demo --agent worker-a",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1\n%2",
            "TMUX_FAKE_TEAM": "demo",
            "TMUX_FAKE_TAG_TEAM": "other-team",
            "TMUX_FAKE_TAG_AGENT": "other-agent",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "pane already stale" in result.stdout
    log_text = log_path.read_text(encoding="utf-8")
    assert "kill-pane -t %2" not in log_text
    cfg = json.loads((state_dir / "teams" / "demo" / "team.json").read_text())
    assert cfg["members"]["worker-a"]["active"] is False
    assert not (state_dir / "archive").exists()


def write_sigterm_ignoring_helper(path):
    path.write_text(
        "#!/bin/sh\n"
        "trap '' TERM\n"
        "[ -n \"$XMUX_TEST_READY_FILE\" ] && : > \"$XMUX_TEST_READY_FILE\"\n"
        "sleep 60\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def write_delayed_sigterm_cleanup_helper(path):
    path.write_text(
        "#!/bin/sh\n"
        "trap 'sleep \"${XMUX_TEST_TERM_DELAY:-0.2}\"; "
        "[ -n \"$XMUX_TEST_PID_FILE\" ] && rm -f \"$XMUX_TEST_PID_FILE\"; "
        "exit 0' TERM\n"
        "[ -n \"$XMUX_TEST_READY_FILE\" ] && : > \"$XMUX_TEST_READY_FILE\"\n"
        "while :; do sleep 60 & wait $!; done\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def wait_for_ready_file(path):
    for _ in range(50):
        if path.exists():
            return
        time.sleep(0.05)
    raise AssertionError(f"{path} was not created")


def parse_key_values(text):
    return dict(line.split("=", 1) for line in text.strip().splitlines() if "=" in line)


def test_xmux_team_shutdown_archives_after_bridge_cleans_up_during_pane_shutdown(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "worker-a", "gemini", pane="%2")

    team_dir = state_dir / "teams" / "demo"
    team_cfg_path = team_dir / "team.json"
    team_cfg = json.loads(team_cfg_path.read_text(encoding="utf-8"))
    team_cfg["status"] = "degraded"
    team_cfg["shutdown"] = {
        "failed_agents": ["worker-a"],
        "failed_at": "2026-04-28T00:00:00Z",
        "reason": "manual-shutdown",
        "status": "degraded",
    }
    team_cfg_path.write_text(json.dumps(team_cfg), encoding="utf-8")

    pid_file = team_dir / ".worker-a-bridge.pid"
    meta_file = team_dir / ".worker-a-bridge.meta"
    helper = tmp_path / "xmux-bridge.zsh"
    ready_file = tmp_path / "bridge-ready"
    write_delayed_sigterm_cleanup_helper(helper)

    env = os.environ.copy()
    env["XMUX_TEST_READY_FILE"] = str(ready_file)
    env["XMUX_TEST_PID_FILE"] = str(pid_file)
    proc = subprocess.Popen(
        [str(helper), "-T", "demo", "-a", "worker-a"],
        env=env,
    )
    try:
        wait_for_ready_file(ready_file)
        pid_file.write_text(f"{proc.pid}\n", encoding="utf-8")
        meta_file.write_text(
            bridge_pid_meta("demo", "worker-a", "bridge", proc.pid, tmp_path, state_dir),
            encoding="utf-8",
        )

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
    if [ -f "$TMUX_FAKE_KILLED" ]; then
      printf '%s\\n' '%1'
    else
      printf '%s\\n%s\\n' '%1' '%2'
    fi
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
    case "$fmt" in
      *@xmux-team*@xmux-agent*)
        if [ "$target" = '%2' ]; then
          printf 'demo\\tworker-a\\n'
        else
          printf 'demo\\tcodex-lead\\n'
        fi
        ;;
      *@xmux-team*@xmux-lead*)
        if [ "$target" = '%1' ]; then
          printf 'demo\\t1\\n'
        else
          printf 'demo\\t\\n'
        fi
        ;;
      '#{session_name}')
        printf 'demo\\n'
        ;;
      *)
        printf '\\n'
        ;;
    esac
    ;;
  kill-pane)
    touch "$TMUX_FAKE_KILLED"
    ;;
  send-keys|select-pane|set-option)
    ;;
esac
""",
            encoding="utf-8",
        )
        tmux.chmod(0o755)

        result = run_zsh(
            "xmux teamShutdown -t demo --timeout 1 --reason manual-shutdown",
            {
                "XMUX_STATE_DIR": str(state_dir),
                "XMUX_INSTALL_DIR": str(tmp_path),
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "TMUX_FAKE_LOG": str(tmp_path / "tmux.log"),
                "TMUX_FAKE_KILLED": str(tmp_path / "pane-killed"),
            },
        )

        assert result.returncode == 0, result.stderr
        assert "shutdown complete team:demo archived:" in result.stdout
        assert not team_dir.exists()
        archive_dirs = sorted((state_dir / "archive").glob("*-demo"))
        assert len(archive_dirs) == 1
        archived_cfg = json.loads(
            (archive_dirs[0] / "team.json").read_text(encoding="utf-8")
        )
        assert archived_cfg["status"] == "archived"
        assert archived_cfg["members"]["worker-a"]["active"] is False
        assert "failed_agents" not in archived_cfg["shutdown"]
        assert "failed_at" not in archived_cfg["shutdown"]
        assert not (archive_dirs[0] / ".worker-a-bridge.pid").exists()
        assert not (archive_dirs[0] / ".worker-a-bridge.meta").exists()
        assert proc.poll() is not None
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)


def test_xmux_guarded_cleanup_preserves_verified_bridge_pid_when_sigterm_ignored(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    team_dir = state_dir / "teams" / "demo"
    team_dir.mkdir(parents=True)
    pid_file = team_dir / ".copilot-worker-bridge.pid"
    meta_file = team_dir / ".copilot-worker-bridge.meta"
    helper = tmp_path / "xmux-bridge.zsh"
    ready_file = tmp_path / "bridge-ready"
    write_sigterm_ignoring_helper(helper)

    env = os.environ.copy()
    env["XMUX_TEST_READY_FILE"] = str(ready_file)
    proc = subprocess.Popen(
        [str(helper), "-T", "demo", "-a", "copilot-worker"],
        env=env,
    )
    try:
        wait_for_ready_file(ready_file)
        pid_file.write_text(f"{proc.pid}\n", encoding="utf-8")
        meta_file.write_text(
            bridge_pid_meta("demo", "copilot-worker", "bridge", proc.pid, tmp_path, state_dir),
            encoding="utf-8",
        )

        result = run_zsh(
            """
cleanup_result="$(_xmux_guarded_cleanup_pid_file "$PID_FILE" "$META_FILE" demo copilot-worker bridge "demo:copilot-worker bridge")"
cleanup_rc=$?
alive=0
kill -0 "$TARGET_PID" 2>/dev/null && alive=1
pid_present=0
[[ -f "$PID_FILE" ]] && pid_present=1
meta_present=0
[[ -f "$META_FILE" ]] && meta_present=1
print -r -- "cleanup_rc=$cleanup_rc"
print -r -- "cleanup_result=$cleanup_result"
print -r -- "alive=$alive"
print -r -- "pid_present=$pid_present"
print -r -- "meta_present=$meta_present"
""",
                {
                    "XMUX_STATE_DIR": str(state_dir),
                    "XMUX_INSTALL_DIR": str(tmp_path),
                    "PID_FILE": str(pid_file),
                    "META_FILE": str(meta_file),
                    "TARGET_PID": str(proc.pid),
            },
        )

        assert result.returncode == 0, result.stderr
        values = parse_key_values(result.stdout)
        assert values["cleanup_rc"] == "1"
        assert values["cleanup_result"] == "kill-failed"
        assert values["alive"] == "1"
        assert values["pid_present"] == "1"
        assert values["meta_present"] == "1"
        assert proc.poll() is None
    finally:
        proc.kill()
        proc.wait(timeout=5)


def test_xmux_guarded_cleanup_preserves_verified_http_pid_when_sigterm_ignored(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    team_dir = state_dir / "teams" / "demo"
    inbox_dir = team_dir / "inboxes"
    inbox_dir.mkdir(parents=True)
    outbox = inbox_dir / "codex-lead.json"
    outbox.write_text("[]\n", encoding="utf-8")
    pid_file = team_dir / ".copilot-worker-mcp-http.pid"
    meta_file = team_dir / ".copilot-worker-mcp-http.json"
    helper = tmp_path / "bridge-mcp-server.js"
    ready_file = tmp_path / "http-ready"
    write_sigterm_ignoring_helper(helper)

    env = os.environ.copy()
    env["XMUX_TEST_READY_FILE"] = str(ready_file)
    proc = subprocess.Popen(
        [
            str(helper),
            "--http",
            "43210",
            "--outbox",
            str(outbox),
            "--agent",
            "copilot-worker",
        ],
        env=env,
    )
    try:
        wait_for_ready_file(ready_file)
        pid_file.write_text(f"{proc.pid}\n", encoding="utf-8")
        meta_file.write_text(
            json.dumps(
                    {
                        "team": "demo",
                        "agent": "copilot-worker",
                        "port": "43210",
                        "server_path": str(helper),
                        "pid": str(proc.pid),
                        "install_dir": str(tmp_path),
                        "project_dir": str(ROOT),
                        "state_dir": str(state_dir),
                    }
                )
            + "\n",
            encoding="utf-8",
        )

        result = run_zsh(
            """
cleanup_result="$(_xmux_guarded_cleanup_pid_file "$PID_FILE" "$META_FILE" demo copilot-worker http_mcp "demo:copilot-worker http mcp")"
cleanup_rc=$?
alive=0
kill -0 "$TARGET_PID" 2>/dev/null && alive=1
pid_present=0
[[ -f "$PID_FILE" ]] && pid_present=1
meta_present=0
[[ -f "$META_FILE" ]] && meta_present=1
print -r -- "cleanup_rc=$cleanup_rc"
print -r -- "cleanup_result=$cleanup_result"
print -r -- "alive=$alive"
print -r -- "pid_present=$pid_present"
print -r -- "meta_present=$meta_present"
""",
                {
                    "XMUX_STATE_DIR": str(state_dir),
                    "XMUX_INSTALL_DIR": str(tmp_path),
                    "PID_FILE": str(pid_file),
                    "META_FILE": str(meta_file),
                    "TARGET_PID": str(proc.pid),
            },
        )

        assert result.returncode == 0, result.stderr
        values = parse_key_values(result.stdout)
        assert values["cleanup_rc"] == "1"
        assert values["cleanup_result"] == "kill-failed"
        assert values["alive"] == "1"
        assert values["pid_present"] == "1"
        assert values["meta_present"] == "1"
        assert proc.poll() is None
    finally:
        proc.kill()
        proc.wait(timeout=5)


def test_xmux_shutdown_agent_fails_and_preserves_verified_bridge_pid_when_sigterm_ignored(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%9")

    team_dir = state_dir / "teams" / "demo"
    pid_file = team_dir / ".copilot-worker-bridge.pid"
    meta_file = team_dir / ".copilot-worker-bridge.meta"
    helper = tmp_path / "xmux-bridge.zsh"
    ready_file = tmp_path / "stop-bridge-ready"
    write_sigterm_ignoring_helper(helper)
    env = os.environ.copy()
    env["XMUX_TEST_READY_FILE"] = str(ready_file)
    proc = subprocess.Popen(
        [str(helper), "-T", "demo", "-a", "copilot-worker"],
        env=env,
    )
    try:
        wait_for_ready_file(ready_file)
        pid_file.write_text(f"{proc.pid}\n", encoding="utf-8")
        meta_file.write_text(
            bridge_pid_meta("demo", "copilot-worker", "bridge", proc.pid, tmp_path, state_dir),
            encoding="utf-8",
        )
        log_path = tmp_path / "tmux.log"
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        write_fake_tmux(bin_dir)

        result = run_zsh(
            "xmux shutdown -t demo --agent copilot-worker",
            {
                "XMUX_STATE_DIR": str(state_dir),
                "XMUX_INSTALL_DIR": str(tmp_path),
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "TMUX_FAKE_LOG": str(log_path),
                "TMUX_FAKE_PANES": "%1",
                "TMUX_FAKE_TEAM": "demo",
            },
        )

        assert result.returncode == 1
        assert "failed to stop verified helper" in result.stderr
        assert proc.poll() is None
        assert pid_file.exists()
        assert meta_file.exists()
        cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
        assert cfg["members"]["copilot-worker"]["active"] is True
    finally:
        proc.kill()
        proc.wait(timeout=5)


def test_xmux_ensure_ready_does_not_kill_unverified_live_bridge_pid(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    project_dir = tmp_path / "project"
    home = tmp_path / "home"
    project_dir.mkdir()
    home.mkdir()
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "gemini-worker", "gemini", pane="%2")

    sleeper = subprocess.Popen(["sleep", "60"])
    try:
        team_dir = state_dir / "teams" / "demo"
        bridge_pid = team_dir / ".gemini-worker-bridge.pid"
        bridge_pid.write_text(f"{sleeper.pid}\n", encoding="utf-8")
        bridge_meta = team_dir / ".gemini-worker-bridge.meta"
        bridge_meta.write_text(
            f"team=demo\nagent=gemini-worker\nkind=bridge\npid={sleeper.pid}\n",
            encoding="utf-8",
        )
        log_path = tmp_path / "tmux.log"
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        write_fake_tmux(bin_dir)

        result = run_zsh(
            "xmux ensure -t demo gemini-worker --ready --json",
            {
                "HOME": str(home),
                "XMUX_PROJECT_DIR": str(project_dir),
                "XMUX_STATE_DIR": str(state_dir),
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "TMUX_FAKE_LOG": str(log_path),
                "TMUX_FAKE_PANES": "%1\n%2",
                "TMUX_FAKE_TEAM": "demo",
                "TMUX_FAKE_TAG_AGENT": "gemini-worker",
                "TMUX_FAKE_LIVE_PID": str(os.getpid()),
                "TMUX_FAKE_BRIDGE_PID_FILE": str(bridge_pid),
            },
        )

        assert result.returncode == 0, result.stderr
        assert sleeper.poll() is None
        target = json.loads(result.stdout)["targets"][0]
        assert "removed unverified bridge pid without killing process" in target["actions"]
        assert bridge_pid.read_text(encoding="utf-8").strip() == str(os.getpid())
    finally:
        sleeper.terminate()
        sleeper.wait(timeout=5)


def test_xmux_ensure_ready_does_not_kill_unverified_live_http_pid(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    project_dir = tmp_path / "project"
    home = tmp_path / "home"
    project_dir.mkdir()
    home.mkdir()
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%2")

    sleeper = subprocess.Popen(["sleep", "60"])
    try:
        team_dir = state_dir / "teams" / "demo"
        bridge_pid = team_dir / ".copilot-worker-bridge.pid"
        bridge_pid.write_text(f"{os.getpid()}\n", encoding="utf-8")
        bridge_meta = team_dir / ".copilot-worker-bridge.meta"
        bridge_meta.write_text(
            f"team=demo\nagent=copilot-worker\nkind=bridge\npid={os.getpid()}\n",
            encoding="utf-8",
        )
        http_pid = team_dir / ".copilot-worker-mcp-http.pid"
        http_pid.write_text(f"{sleeper.pid}\n", encoding="utf-8")
        http_meta = team_dir / ".copilot-worker-mcp-http.json"
        http_meta.write_text(
            json.dumps(
                {
                    "team": "demo",
                    "agent": "copilot-worker",
                    "port": "43210",
                    "server_path": str(ROOT / "bridge-mcp-server.js"),
                    "pid": str(sleeper.pid),
                }
            )
            + "\n",
            encoding="utf-8",
        )
        log_path = tmp_path / "tmux.log"
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        write_fake_tmux(bin_dir)
        curl = bin_dir / "curl"
        curl.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        curl.chmod(0o755)

        result = run_zsh(
            "xmux ensure -t demo copilot-worker --ready --json",
            {
                "HOME": str(home),
                "XMUX_PROJECT_DIR": str(project_dir),
                "XMUX_STATE_DIR": str(state_dir),
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "TMUX_FAKE_LOG": str(log_path),
                "TMUX_FAKE_PANES": "%1\n%2",
                "TMUX_FAKE_TEAM": "demo",
                "TMUX_FAKE_TAG_AGENT": "copilot-worker",
                "TMUX_FAKE_LIVE_PID": str(os.getpid()),
                "TMUX_FAKE_BRIDGE_PID_FILE": str(bridge_pid),
                "TMUX_FAKE_HTTP_PID_FILE": str(http_pid),
            },
        )

        assert result.returncode == 0, result.stderr
        assert sleeper.poll() is None
        target = json.loads(result.stdout)["targets"][0]
        assert (
            "removed unverified Copilot HTTP MCP pid without killing process"
            in target["actions"]
        )
        assert http_pid.read_text(encoding="utf-8").strip() == str(os.getpid())
    finally:
        sleeper.terminate()
        sleeper.wait(timeout=5)


def test_xmux_shutdown_agent_handles_dead_pane_member_state(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%9")
    xmux_mailbox.enqueue_request(
        "demo",
        "copilot-worker",
        from_name="codex-lead",
        message="ping",
        request_id="req-stays",
    )

    team_dir = state_dir / "teams" / "demo"
    bridge_pid = team_dir / ".copilot-worker-bridge.pid"
    http_pid = team_dir / ".copilot-worker-mcp-http.pid"
    bridge_pid.write_text("999999\n", encoding="utf-8")
    http_pid.write_text("999999\n", encoding="utf-8")
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux shutdown -t demo --agent copilot-worker",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1",
            "TMUX_FAKE_TEAM": "demo",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "pane already dead" in result.stdout
    assert not bridge_pid.exists()
    assert not http_pid.exists()
    cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    assert cfg["members"]["copilot-worker"]["active"] is False
    assert not (state_dir / "archive").exists()
    assert (team_dir / "requests" / "req-stays.json").is_file()
    assert "kill-pane -t %9" not in log_path.read_text(encoding="utf-8")


def test_xmux_shutdown_accepts_multiple_agents_without_archiving(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%9")
    xmux_mailbox.register_member("demo", "gemini-worker", "gemini", pane="%8")

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_fake_tmux(bin_dir)

    result = run_zsh(
        "xmux shutdown -t demo --agent copilot-worker --agent gemini-worker",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_PANES": "%1",
            "TMUX_FAKE_TEAM": "demo",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "agents:copilot-worker,gemini-worker archived:false" in result.stdout
    team_dir = state_dir / "teams" / "demo"
    cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    assert cfg["members"]["copilot-worker"]["active"] is False
    assert cfg["members"]["gemini-worker"]["active"] is False
    assert not (state_dir / "archive").exists()


def test_xmux_shutdown_agent_does_not_kill_unverified_live_pid_files(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member("demo", "copilot-worker", "copilot", pane="%9")

    bridge_proc = subprocess.Popen(["sleep", "60"])
    http_proc = subprocess.Popen(["sleep", "60"])
    try:
        team_dir = state_dir / "teams" / "demo"
        bridge_pid = team_dir / ".copilot-worker-bridge.pid"
        http_pid = team_dir / ".copilot-worker-mcp-http.pid"
        bridge_pid.write_text(f"{bridge_proc.pid}\n", encoding="utf-8")
        http_pid.write_text(f"{http_proc.pid}\n", encoding="utf-8")
        bridge_meta = team_dir / ".copilot-worker-bridge.meta"
        http_meta = team_dir / ".copilot-worker-mcp-http.json"
        bridge_meta.write_text(
            f"team=demo\nagent=copilot-worker\nkind=bridge\npid={bridge_proc.pid}\n",
            encoding="utf-8",
        )
        http_meta.write_text(
            json.dumps(
                {
                    "team": "demo",
                    "agent": "copilot-worker",
                    "port": "43210",
                    "server_path": str(ROOT / "bridge-mcp-server.js"),
                    "pid": str(http_proc.pid),
                }
            )
            + "\n",
            encoding="utf-8",
        )
        log_path = tmp_path / "tmux.log"
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        write_fake_tmux(bin_dir)

        result = run_zsh(
            "xmux shutdown -t demo --agent copilot-worker",
            {
                "XMUX_STATE_DIR": str(state_dir),
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "TMUX_FAKE_LOG": str(log_path),
                "TMUX_FAKE_PANES": "%1",
                "TMUX_FAKE_TEAM": "demo",
            },
        )

        assert result.returncode == 0, result.stderr
        assert bridge_proc.poll() is None
        assert http_proc.poll() is None
        assert not bridge_pid.exists()
        assert not http_pid.exists()
        assert not bridge_meta.exists()
        assert not http_meta.exists()
        assert "cleanup:bridge=removed-unverified http=removed-unverified" in result.stdout
    finally:
        bridge_proc.terminate()
        http_proc.terminate()
        bridge_proc.wait(timeout=5)
        http_proc.wait(timeout=5)


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


def test_xmux_shutdown_agent_restores_lead_focus_before_and_after_kill(
    tmp_path, monkeypatch
):
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
      [ "$target" = '%%2' -o "$target" = '%2' ] && printf 'copilot-worker\\n'
    elif [ "$fmt" = '#{@xmux-team}' ]; then
      [ "$target" = '%%2' -o "$target" = '%2' ] && printf 'StopUX\\n'
    elif case "$fmt" in *@xmux-team*@xmux-agent*) true ;; *) false ;; esac; then
      [ "$target" = '%%2' -o "$target" = '%2' ] && printf '%s\\t%s\\n' 'StopUX' 'copilot-worker'
    elif [ "$fmt" = '#{@xmux-lead}' ]; then
      [ "$target" = '%%1' -o "$target" = '%1' ] && printf '1\\n'
    elif [ "$target" = '%%2' -o "$target" = '%2' ]; then
      printf '%s\\t%s\\n' 'StopUX' 'copilot-worker'
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
    result = run_zsh("xmux shutdown -t StopUX --agent copilot-worker", env)

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    first_select = lines.index("select-pane -t %1")
    kill_pane = lines.index("kill-pane -t %2")
    last_select = len(lines) - 1 - lines[::-1].index("select-pane -t %1")
    assert first_select < kill_pane < last_select


def test_xmux_stop_subcommand_is_removed(tmp_path):
    result = run_zsh(
        "xmux stop -t demo copilot-worker",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 1
    assert "unknown xmux command 'stop'" in result.stderr
    assert "deprecated" not in result.stderr


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


def test_prepare_codex_runtime_does_not_mutate_canonical_codex_home(tmp_path):
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
    assert not config_path.exists()
    assert "run 'xmux setup-codex'" in result.stderr
    assert not (home / ".codex" / "plugins" / "cache" / "xmux-local").exists()


def test_xmux_plugin_exposes_skills_without_slash_commands():
    assert (ROOT / ".agents" / "plugins" / "marketplace.json").is_file()
    assert (ROOT / "plugins" / "xmux" / ".codex-plugin" / "plugin.json").is_file()
    commands_dir = ROOT / "plugins" / "xmux" / "commands"
    assert not list(commands_dir.glob("*.md"))

    for skill in (
        "xmux-teams",
        "xmux-claude",
        "xmux-gemini",
        "xmux-copilot",
        "xmux-diagnosis",
        "xmux-send-pane",
    ):
        skill_path = ROOT / "plugins" / "xmux" / "skills" / skill / "SKILL.md"
        mirror_path = ROOT / "skills" / skill / "SKILL.md"
        metadata_path = ROOT / "plugins" / "xmux" / "skills" / skill / "agents" / "openai.yaml"
        mirror_metadata_path = ROOT / "skills" / skill / "agents" / "openai.yaml"
        assert skill_path.is_file()
        assert mirror_path.is_file()
        assert skill_path.read_text(encoding="utf-8") == mirror_path.read_text(encoding="utf-8")
        assert f"${skill}" in skill_path.read_text(encoding="utf-8")
        assert metadata_path.is_file()
        assert mirror_metadata_path.is_file()
        metadata_text = metadata_path.read_text(encoding="utf-8")
        assert metadata_text == mirror_metadata_path.read_text(encoding="utf-8")
        assert f'display_name: "{skill}"' in metadata_text
        assert f"${skill}" in metadata_text


def test_xmux_plugin_skills_use_xmux_namespace_only():
    plugin_files = list((ROOT / "plugins" / "xmux" / "skills").glob("*/SKILL.md"))
    text = "\n".join(path.read_text(encoding="utf-8") for path in plugin_files)

    assert "/xmux-" not in text
    assert "/a" + "mux-" not in text
    assert "/cl" + "mux-" not in text
    assert "name: a" + "mux-" not in text
    assert "name: cl" + "mux-" not in text
    assert "/xmux-codex" not in text
    assert "name: xmux-codex" not in text
