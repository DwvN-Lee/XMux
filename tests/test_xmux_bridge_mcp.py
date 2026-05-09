import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"
BRIDGE = ROOT / "bridge-mcp-server.js"


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


def test_bridge_mcp_supports_content_length_framing_without_stdin_close(tmp_path):
    env = os.environ.copy()
    env.update({
        "XMUX_STATE_DIR": str(tmp_path / "xmux-state"),
        "XMUX_INSTALL_DIR": str(ROOT),
        "XMUX_TEAM": "demo",
        "XMUX_OUTBOX": str(tmp_path / "xmux-state" / "teams" / "demo" / "inboxes" / "codex-lead.json"),
        "XMUX_AGENT": "gemini-worker",
    })
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
        assert response["result"]["serverInfo"]["name"] == "xmux-bridge"
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def test_bridge_write_to_lead_writes_xmux_response_with_request_id(tmp_path):
    state_dir = tmp_path / "xmux-state"
    team = "bridge-mcp-team"
    request_id = "req-bridge-001"
    outbox = state_dir / "teams" / team / "inboxes" / "codex-lead.json"
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
        "gemini-worker",
        "--provider",
        "gemini",
    )

    env = os.environ.copy()
    env.update({
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_INSTALL_DIR": str(install_dir),
        "XMUX_TEAM": team,
        "XMUX_OUTBOX": str(outbox),
        "XMUX_AGENT": "gemini-worker",
        "XMUX_TEST_NODE_MAILBOX_LOG": str(node_log),
    })
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
        "method": "initialize",
        "params": {"protocolVersion": "2024-11-05"},
    }) + "\n")
    proc.stdin.write(json.dumps({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_to_lead",
            "arguments": {
                "text": "analysis complete",
                "summary": "done",
                "request_id": request_id,
            },
        },
    }) + "\n")
    proc.stdin.close()

    responses = [json.loads(proc.stdout.readline()), json.loads(proc.stdout.readline())]
    stderr = proc.stderr.read() if proc.stderr is not None else ""
    assert proc.wait(timeout=10) == 0, stderr
    by_id = {resp["id"]: resp for resp in responses}
    assert by_id[1]["result"]["serverInfo"]["name"] == "xmux-bridge"
    assert by_id[2]["result"]["content"][0]["text"] == "ok: response delivered to lead"

    read = _run_mailbox(state_dir, "read-response", team, request_id)
    assert read["status"] == "done"
    assert read["response"]["from"] == "gemini-worker"
    assert read["response"]["text"] == "analysis complete"
    assert read["response"]["summary"] == "done"

    invocations = [
        json.loads(line)["argv"][0]
        for line in node_log.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert "write-response" in invocations


def test_bridge_write_to_lead_rejects_unregistered_xmux_agent(tmp_path):
    state_dir = tmp_path / "xmux-state"
    team = "bridge-mcp-team"
    request_id = "req-bridge-unregistered"
    outbox = state_dir / "teams" / team / "inboxes" / "codex-lead.json"

    _run_mailbox(
        state_dir,
        "init-team",
        team,
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
    )

    env = os.environ.copy()
    env.update({
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_INSTALL_DIR": str(ROOT),
        "XMUX_TEAM": team,
        "XMUX_OUTBOX": str(outbox),
        "XMUX_AGENT": "claude-worker",
    })
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
                "text": "spoofed source",
                "request_id": request_id,
            },
        },
    }) + "\n")
    proc.stdin.close()

    response = json.loads(proc.stdout.readline())
    stderr = proc.stderr.read() if proc.stderr is not None else ""
    assert proc.wait(timeout=10) == 0, stderr
    assert (
        response["result"]["content"][0]["text"]
        == "error: xmux mailbox write failed: xmux-mailbox: response sender not registered or inactive: claude-worker"
    )
    assert json.loads(outbox.read_text(encoding="utf-8")) == []
    assert not (state_dir / "teams" / team / "requests" / f"{request_id}.json").exists()
