import json
import os
import queue
import subprocess
import sys
import threading
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "xmux-lead-mcp-server.js"
MAILBOX = ROOT / "scripts" / "xmux_mailbox.py"


class McpSession:
    def __init__(self, state_dir: Path):
        env = os.environ.copy()
        env["XMUX_STATE_DIR"] = str(state_dir)
        env["PYTHON"] = sys.executable
        state_dir.mkdir(parents=True, exist_ok=True)

        self.proc = subprocess.Popen(
            ["node", str(SERVER)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
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


def _run_mailbox(state_dir: Path, *args):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)
    result = subprocess.run(
        [sys.executable, str(MAILBOX), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def _assert_not_server_cli_error(payload):
    internal_errors = {
        "mailbox_cli_missing",
        "mailbox_cli_spawn_failed",
        "mailbox_cli_empty_output",
        "mailbox_cli_invalid_json",
        "mailbox_cli_failed",
    }
    assert payload.get("error") not in internal_errors, payload


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


@pytest.mark.skipif(not MAILBOX.exists(), reason="scripts/xmux_mailbox.py is not present yet")
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
        "worker-a",
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
                    "to": "worker-a",
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
            "worker-a",
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
