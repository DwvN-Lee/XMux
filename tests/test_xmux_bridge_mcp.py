import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "scripts" / "xmux_mailbox.py"
BRIDGE = ROOT / "bridge-mcp-server.js"


def _run_mailbox(xmux_home: Path, *args):
    env = os.environ.copy()
    env["XMUX_HOME"] = str(xmux_home)
    result = subprocess.run(
        [sys.executable, str(MAILBOX), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_bridge_write_to_lead_writes_xmux_response_with_request_id(tmp_path):
    xmux_home = tmp_path / "xmux-home"
    team = "bridge-mcp-team"
    request_id = "req-bridge-001"
    outbox = xmux_home / "teams" / team / "inboxes" / "codex-lead.json"

    _run_mailbox(
        xmux_home,
        "init-team",
        team,
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
    )

    env = os.environ.copy()
    env.update({
        "XMUX_HOME": str(xmux_home),
        "XMUX_DIR": str(ROOT),
        "XMUX_TEAM": team,
        "XMUX_OUTBOX": str(outbox),
        "XMUX_AGENT": "gemini-worker",
        "PYTHON": sys.executable,
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

    read = _run_mailbox(xmux_home, "read-response", team, request_id)
    assert read["status"] == "done"
    assert read["response"]["from"] == "gemini-worker"
    assert read["response"]["text"] == "analysis complete"
    assert read["response"]["summary"] == "done"
