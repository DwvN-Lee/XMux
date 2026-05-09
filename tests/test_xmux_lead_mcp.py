import json
import os
import queue
import subprocess
import threading
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "xmux-lead-mcp-server.js"
BRIDGE = ROOT / "bridge-mcp-server.js"
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"


class McpSession:
    def __init__(self, state_dir: Path, env_overrides=None, set_state_dir=True, cwd=None):
        env = os.environ.copy()
        env.pop("XMUX_INSTALL_DIR", None)
        env.pop("XMUX_PROJECT_DIR", None)
        env.pop("XMUX_STATE_DIR", None)
        if set_state_dir:
            env["XMUX_STATE_DIR"] = str(state_dir)
        if env_overrides:
            for key, value in env_overrides.items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
        state_dir.mkdir(parents=True, exist_ok=True)

        self.proc = subprocess.Popen(
            ["node", str(SERVER)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            cwd=cwd,
        )
        self._next_id = 1
        self._stdout = queue.Queue()
        self._reader = threading.Thread(target=self._read_stdout, daemon=True)
        self._reader.start()

    def _read_stdout(self):
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            self._stdout.put(line)

    def request(self, method, params=None):
        msg_id = self._next_id
        self._next_id += 1
        msg = {"jsonrpc": "2.0", "id": msg_id, "method": method}
        if params is not None:
            msg["params"] = params
        self._write(msg)

        try:
            line = self._stdout.get(timeout=5)
        except queue.Empty:
            raise AssertionError(f"timed out waiting for MCP response to {method}")

        response = json.loads(line)
        assert response["id"] == msg_id
        return response

    def notify(self, method, params=None):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self._write(msg)

    def call_tool(self, name, arguments):
        return self.request("tools/call", {"name": name, "arguments": arguments})

    def _write(self, msg):
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def close(self):
        if self.proc.stdin is not None:
            try:
                self.proc.stdin.close()
            except BrokenPipeError:
                pass
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=2)


def _tool_payload(response):
    assert "error" not in response
    content = response["result"]["content"]
    assert content and content[0]["type"] == "text"
    return json.loads(content[0]["text"])


def _mcp_frame(message):
    body = json.dumps(message, separators=(",", ":"))
    return f"Content-Length: {len(body.encode('utf-8'))}\r\n\r\n{body}"


def _read_mcp_frame(stdout):
    headers = []
    while True:
        line = stdout.readline()
        assert line, "MCP server closed stdout before response headers"
        if line in ("\n", "\r\n"):
            break
        headers.append(line.strip())
    length = None
    for header in headers:
        if header.lower().startswith("content-length:"):
            length = int(header.split(":", 1)[1].strip())
            break
    assert length is not None, headers
    return json.loads(stdout.read(length))


def _run_mailbox(state_dir: Path, *args):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)
    result = subprocess.run(
        ["node", str(MAILBOX), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def _write_active_team_registry(registry_dir: Path, team: str, project_dir: Path, state_dir: Path):
    registry_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "xmux.active_team.v1",
        "team": team,
        "project_dir": str(project_dir),
        "state_dir": str(state_dir),
        "team_dir": str(state_dir / "teams" / team),
        "session": f"xmux-{team}",
        "lead_pane": "%1",
        "status": "active",
        "updated_at": "2026-05-09T00:00:00.000Z",
    }
    (registry_dir / f"{team}.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _write_node_mailbox_proxy(install_dir: Path):
    cli = install_dir / "dist" / "bin" / "xmux-mailbox.js"
    cli.parent.mkdir(parents=True, exist_ok=True)
    cli.write_text(
        "\n".join(
            [
                "#!/usr/bin/env node",
                "'use strict';",
                "const fs = require('fs');",
                f"const cli = require({json.dumps(str(ROOT / 'src' / 'mailbox' / 'cli.js'))});",
                "const logPath = process.env.XMUX_TEST_NODE_MAILBOX_LOG;",
                "if (logPath) fs.appendFileSync(logPath, JSON.stringify({ argv: process.argv.slice(2) }) + '\\n');",
                "process.exit(cli.main(process.argv.slice(2)));",
                "",
            ]
        ),
        encoding="utf-8",
    )
    cli.chmod(0o755)
    return cli


def _call_bridge_write_to_lead(
    state_dir: Path,
    *,
    team: str,
    agent: str,
    text: str,
    summary: str,
    request_id: str,
    env_overrides=None,
):
    outbox = state_dir / "teams" / team / "inboxes" / "codex-lead.json"
    env = os.environ.copy()
    env.update({
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_INSTALL_DIR": str(ROOT),
        "XMUX_TEAM": team,
        "XMUX_OUTBOX": str(outbox),
        "XMUX_AGENT": agent,
    })
    if env_overrides:
        env.update(env_overrides)
    proc = subprocess.Popen(
        ["node", str(BRIDGE)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None

    proc.stdin.write(json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "write_to_lead",
            "arguments": {
                "text": text,
                "summary": summary,
                "request_id": request_id,
            },
        },
    }) + "\n")
    proc.stdin.close()

    response = json.loads(proc.stdout.readline())
    stderr = proc.stderr.read() if proc.stderr is not None else ""
    assert proc.wait(timeout=10) == 0, stderr
    return response["result"]["content"][0]["text"]


def _assert_not_server_cli_error(payload):
    internal_errors = {
        "mailbox_cli_missing",
        "mailbox_cli_spawn_failed",
        "mailbox_cli_empty_output",
        "mailbox_cli_invalid_json",
        "mailbox_cli_failed",
    }
    assert payload.get("error") not in internal_errors, payload


def test_lead_mcp_supports_content_length_framing_without_stdin_close(tmp_path):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / "xmux-state")
    proc = subprocess.Popen(
        ["node", str(SERVER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None
    try:
        proc.stdin.write(_mcp_frame({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": "2024-11-05"},
        }))
        proc.stdin.flush()

        response = _read_mcp_frame(proc.stdout)
        assert response["id"] == 1
        assert response["result"]["serverInfo"]["name"] == "xmux-lead"
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def test_lead_mcp_uses_xmux_install_dir_for_mailbox_script(tmp_path):
    install_dir = tmp_path / "libexec"
    cli = install_dir / "dist" / "bin" / "xmux-mailbox.js"
    cli.parent.mkdir(parents=True, exist_ok=True)
    cli.write_text(
        "\n".join(
            [
                "#!/usr/bin/env node",
                "'use strict';",
                "const payload = { ok: true, source: 'install-dir', command: process.argv[2] };",
                "if (process.argv[3]) payload.team = process.argv[3];",
                "console.log(JSON.stringify(payload));",
                "",
            ]
        ),
        encoding="utf-8",
    )
    cli.chmod(0o755)

    session = McpSession(
        tmp_path / "xmux-state",
        {
            "XMUX_INSTALL_DIR": str(install_dir),
        },
    )
    try:
        payload = _tool_payload(session.call_tool("team_status", {"team": "demo"}))
        assert payload == {
            "ok": True,
            "source": "install-dir",
            "command": "team-status",
            "team": "demo",
        }
    finally:
        session.close()


def test_initialize_tools_list_resources_and_safe_listing_call(tmp_path):
    session = McpSession(tmp_path / "xmux-home")
    try:
        init = session.request("initialize", {"protocolVersion": "2024-11-05"})
        assert init["result"]["protocolVersion"] == "2024-11-05"
        assert init["result"]["serverInfo"]["name"] == "xmux-lead"
        assert "tools" in init["result"]["capabilities"]

        session.notify("notifications/initialized")

        tools = session.request("tools/list")
        names = {tool["name"] for tool in tools["result"]["tools"]}
        assert {
            "send_to_teammate",
            "wait_teammate_response",
            "read_teammate_response",
            "list_teammate_events",
            "team_status",
        }.issubset(names)

        resources = session.request("resources/list")
        assert resources["result"]["resources"] == []

        templates = session.request("resources/templates/list")
        assert templates["result"]["resourceTemplates"] == []

        listing = _tool_payload(
            session.call_tool("list_teammate_events", {"team": "mcp-test-team"})
        )
        assert isinstance(listing, dict)
        if not MAILBOX.exists():
            assert listing["status"] == "not_implemented"
    finally:
        session.close()


def test_send_reports_json_error_until_mailbox_cli_exists(tmp_path):
    if MAILBOX.exists():
        pytest.skip("covered by the mailbox-backed MCP test")

    session = McpSession(tmp_path / "xmux-home")
    try:
        payload = _tool_payload(
            session.call_tool(
                "send_to_teammate",
                {
                    "team": "mcp-test-team",
                    "to": "worker-a",
                    "message": "hello",
                    "request_id": "req-missing-cli",
                },
            )
        )
        assert payload["error"] == "mailbox_cli_missing"
        assert payload["command"] == "enqueue-request"
    finally:
        session.close()


@pytest.mark.skipif(not MAILBOX.exists(), reason="dist/bin/xmux-mailbox.js is not present yet")
def test_send_read_wait_and_status_delegate_to_mailbox_cli(tmp_path):
    state_dir = tmp_path / "xmux-state"
    team = "mcp-test-team"
    request_id = "req-mcp-001"

    _run_mailbox(
        state_dir,
        "init-team",
        team,
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
    )
    _run_mailbox(
        state_dir,
        "register-member",
        team,
        "gemini-worker",
        "--provider",
        "gemini",
        "--backend",
        "tmux",
    )

    session = McpSession(state_dir)
    try:
        sent = _tool_payload(
            session.call_tool(
                "send_to_teammate",
                {
                    "team": team,
                    "to": "gemini",
                    "message": "deterministic mailbox probe",
                    "request_id": request_id,
                },
            )
        )
        _assert_not_server_cli_error(sent)
        assert sent["status"] == "pending"
        assert sent["request_id"] == request_id

        response = _run_mailbox(
            state_dir,
            "write-response",
            team,
            "--from",
            "gemini-worker",
            "--text",
            "mailbox response",
            "--summary",
            "done",
            "--request-id",
            request_id,
        )
        assert response["status"] == "done"

        read = _tool_payload(
            session.call_tool(
                "read_teammate_response",
                {"team": team, "request_id": request_id, "mark_read": False},
            )
        )
        _assert_not_server_cli_error(read)
        assert read["status"] == "done"
        assert read["response"]["text"] == "mailbox response"

        waited = _tool_payload(
            session.call_tool(
                "wait_teammate_response",
                {
                    "team": team,
                    "request_id": request_id,
                    "timeout_sec": 0.5,
                    "interval_sec": 0.01,
                    "mark_read": True,
                },
            )
        )
        _assert_not_server_cli_error(waited)
        assert waited["status"] == "done"
        assert waited["marked_read"] == 1

        status = _tool_payload(session.call_tool("team_status", {"team": team}))
        _assert_not_server_cli_error(status)
        assert status["status"] == "ok"
        assert status["requests"]["done"] == 1
    finally:
        session.close()


@pytest.mark.skipif(not MAILBOX.exists(), reason="dist/bin/xmux-mailbox.js is not present yet")
def test_codex_to_claude_to_codex_dataflow_over_mcp_and_mailbox(tmp_path):
    state_dir = tmp_path / "xmux-state"
    team = "claude-flow-team"
    request_id = "req-claude-flow-001"
    install_dir = tmp_path / "xmux-install"
    node_log = tmp_path / "node-mailbox.log"
    _write_node_mailbox_proxy(install_dir)

    _run_mailbox(
        state_dir,
        "init-team",
        team,
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
    )
    _run_mailbox(
        state_dir,
        "register-member",
        team,
        "claude-worker",
        "--provider",
        "claude",
        "--backend",
        "tmux",
    )

    node_env = {
        "XMUX_INSTALL_DIR": str(install_dir),
        "XMUX_TEST_NODE_MAILBOX_LOG": str(node_log),
    }
    session = McpSession(state_dir, node_env)
    try:
        sent = _tool_payload(
            session.call_tool(
                "send_to_teammate",
                {
                    "team": team,
                    "to": "claude",
                    "message": "inspect the dataflow contract",
                    "request_id": request_id,
                },
            )
        )
        _assert_not_server_cli_error(sent)
        assert sent == {
            "status": "pending",
            "request_id": request_id,
            "to": "claude-worker",
        }

        claude_inbox = json.loads(
            (state_dir / "teams" / team / "inboxes" / "claude-worker.json")
            .read_text(encoding="utf-8")
        )
        assert claude_inbox == [
            {
                "id": claude_inbox[0]["id"],
                "type": "request",
                "request_id": request_id,
                "from": "codex-lead",
                "to": "claude-worker",
                "text": "inspect the dataflow contract",
                "timestamp": claude_inbox[0]["timestamp"],
                "read": False,
                "status": "pending",
            }
        ]

        bridge_result = _call_bridge_write_to_lead(
            state_dir,
            team=team,
            agent="claude-worker",
            text="claude received and completed the probe",
            summary="claude done",
            request_id=request_id,
            env_overrides=node_env,
        )
        assert bridge_result == "ok: response delivered to lead"

        read = _tool_payload(
            session.call_tool(
                "read_teammate_response",
                {"team": team, "request_id": request_id, "mark_read": False},
            )
        )
        _assert_not_server_cli_error(read)
        assert read["status"] == "done"
        assert read["response"]["text"] == "claude received and completed the probe"

        waited = _tool_payload(
            session.call_tool(
                "wait_teammate_response",
                {
                    "team": team,
                    "request_id": request_id,
                    "timeout_sec": 0.5,
                    "interval_sec": 0.01,
                    "mark_read": True,
                },
            )
        )
        _assert_not_server_cli_error(waited)
        assert waited["status"] == "done"
        assert waited["request_id"] == request_id
        assert waited["response"]["from"] == "claude-worker"
        assert waited["response"]["to"] == "codex-lead"
        assert waited["response"]["text"] == "claude received and completed the probe"
        assert waited["response"]["summary"] == "claude done"
        assert waited["marked_read"] == 1

        invocations = [
            json.loads(line)["argv"][0]
            for line in node_log.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        assert "enqueue-request" in invocations
        assert "write-response" in invocations
        assert "read-response" in invocations
        assert "wait-response" in invocations
    finally:
        session.close()


@pytest.mark.skipif(not MAILBOX.exists(), reason="dist/bin/xmux-mailbox.js is not present yet")
def test_lead_mcp_resolves_non_git_project_state_from_active_registry(tmp_path):
    project_dir = tmp_path / "non-git-project"
    state_dir = project_dir / ".codex" / "xmux"
    registry_dir = tmp_path / "home" / ".codex" / "xmux" / "active-teams"
    unrelated_cwd = tmp_path / "unrelated-cwd"
    team = "non-git-project-demo-001"
    request_id = "req-registry-001"
    project_dir.mkdir()
    unrelated_cwd.mkdir()

    _run_mailbox(
        state_dir,
        "init-team",
        team,
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
    )
    _run_mailbox(
        state_dir,
        "register-member",
        team,
        "claude-worker",
        "--provider",
        "claude",
        "--backend",
        "tmux",
    )
    _write_active_team_registry(registry_dir, team, project_dir, state_dir)

    session = McpSession(
        state_dir,
        {"XMUX_ACTIVE_TEAM_REGISTRY_DIR": str(registry_dir)},
        set_state_dir=False,
        cwd=unrelated_cwd,
    )
    try:
        status = _tool_payload(session.call_tool("team_status", {"team": team}))
        _assert_not_server_cli_error(status)
        assert status["status"] == "ok"
        assert status["team_dir"] == str(state_dir / "teams" / team)

        sent = _tool_payload(
            session.call_tool(
                "send_to_teammate",
                {
                    "team": team,
                    "to": "claude",
                    "message": "registry-routed request",
                    "request_id": request_id,
                },
            )
        )
        _assert_not_server_cli_error(sent)
        assert sent["status"] == "pending"
        assert sent["request_id"] == request_id
        assert (state_dir / "teams" / team / "requests" / f"{request_id}.json").is_file()
        assert not (unrelated_cwd / ".codex" / "xmux").exists()

        response = _run_mailbox(
            state_dir,
            "write-response",
            team,
            "--from",
            "claude-worker",
            "--text",
            "registry-routed response",
            "--request-id",
            request_id,
        )
        assert response["status"] == "done"

        waited = _tool_payload(
            session.call_tool(
                "wait_teammate_response",
                {
                    "team": team,
                    "request_id": request_id,
                    "timeout_sec": 0.5,
                    "interval_sec": 0.01,
                    "mark_read": True,
                },
            )
        )
        _assert_not_server_cli_error(waited)
        assert waited["status"] == "done"
        assert waited["response"]["text"] == "registry-routed response"
        assert waited["marked_read"] == 1
    finally:
        session.close()


@pytest.mark.skipif(not MAILBOX.exists(), reason="dist/bin/xmux-mailbox.js is not present yet")
def test_lead_mcp_ignores_stale_active_registry(tmp_path):
    project_dir = tmp_path / "project"
    stale_state_dir = project_dir / ".codex" / "xmux"
    registry_dir = tmp_path / "home" / ".codex" / "xmux" / "active-teams"
    unrelated_cwd = tmp_path / "unrelated-cwd"
    team = "stale-registry-demo"
    project_dir.mkdir()
    stale_state_dir.mkdir(parents=True)
    unrelated_cwd.mkdir()
    _write_active_team_registry(registry_dir, team, project_dir, stale_state_dir)

    session = McpSession(
        stale_state_dir,
        {"XMUX_ACTIVE_TEAM_REGISTRY_DIR": str(registry_dir)},
        set_state_dir=False,
        cwd=unrelated_cwd,
    )
    try:
        status = _tool_payload(session.call_tool("team_status", {"team": team}))
        assert status["status"] == "missing"

        sent = _tool_payload(
            session.call_tool(
                "send_to_teammate",
                {
                    "team": team,
                    "to": "claude",
                    "message": "must not create request in stale state",
                    "request_id": "req-stale-001",
                },
            )
        )
        assert sent["error"] == "mailbox_cli_failed"
        assert not (stale_state_dir / "teams" / team / "requests").exists()
        assert not (unrelated_cwd / ".codex" / "xmux").exists()
    finally:
        session.close()
