import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"


def _run_mailbox(*args: str, env: dict) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["node", str(MAILBOX), *args],
        env=env,
        capture_output=True,
        text=True,
    )


def test_node_mailbox_codex_to_claude_enqueue_request(tmp_path):
    state_dir = tmp_path / ".xmux"
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)

    init = _run_mailbox(
        "init-team",
        "demo",
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
        env=env,
    )
    assert init.returncode == 0, init.stderr

    register = _run_mailbox(
        "register-member",
        "demo",
        "claude-worker",
        "--provider",
        "claude",
        "--pane",
        "%2",
        env=env,
    )
    assert register.returncode == 0, register.stderr

    enqueue = _run_mailbox(
        "enqueue-request",
        "demo",
        "claude",
        "--from",
        "codex-lead",
        "--message",
        "inspect latest failing trace",
        "--request-id",
        "req-codex-claude-001",
        env=env,
    )
    assert enqueue.returncode == 0, enqueue.stderr
    payload = json.loads(enqueue.stdout)
    assert payload == {
        "status": "pending",
        "request_id": "req-codex-claude-001",
        "to": "claude-worker",
    }

    team_dir = state_dir / "teams" / "demo"
    inbox = json.loads((team_dir / "inboxes" / "claude-worker.json").read_text())
    assert len(inbox) == 1
    assert inbox[0]["type"] == "request"
    assert inbox[0]["request_id"] == "req-codex-claude-001"
    assert inbox[0]["from"] == "codex-lead"
    assert inbox[0]["to"] == "claude-worker"
    assert inbox[0]["status"] == "pending"
    assert inbox[0]["read"] is False


def test_node_mailbox_claude_to_codex_response_and_active_sender_validation(tmp_path):
    state_dir = tmp_path / ".xmux"
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)

    init = _run_mailbox(
        "init-team",
        "demo",
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
        env=env,
    )
    assert init.returncode == 0, init.stderr

    register = _run_mailbox(
        "register-member",
        "demo",
        "claude-worker",
        "--provider",
        "claude",
        env=env,
    )
    assert register.returncode == 0, register.stderr

    enqueue = _run_mailbox(
        "enqueue-request",
        "demo",
        "claude-worker",
        "--from",
        "codex-lead",
        "--message",
        "summarize the issue",
        "--request-id",
        "req-codex-claude-002",
        env=env,
    )
    assert enqueue.returncode == 0, enqueue.stderr

    written = _run_mailbox(
        "write-response",
        "demo",
        "--from",
        "claude-worker",
        "--text",
        "analysis complete",
        "--summary",
        "complete",
        "--request-id",
        "req-codex-claude-002",
        env=env,
    )
    assert written.returncode == 0, written.stderr
    written_payload = json.loads(written.stdout)
    assert written_payload["status"] == "done"
    assert written_payload["request_id"] == "req-codex-claude-002"

    read = _run_mailbox(
        "read-response",
        "demo",
        "req-codex-claude-002",
        "--mark-read",
        env=env,
    )
    assert read.returncode == 0, read.stderr
    read_payload = json.loads(read.stdout)
    assert read_payload["status"] == "done"
    assert read_payload["request_id"] == "req-codex-claude-002"
    assert read_payload["response"]["from"] == "claude-worker"
    assert read_payload["response"]["to"] == "codex-lead"
    assert read_payload["response"]["text"] == "analysis complete"
    assert read_payload["response"]["summary"] == "complete"
    assert read_payload["marked_read"] == 1

    update = _run_mailbox(
        "update-member",
        "demo",
        "claude-worker",
        "--active",
        "false",
        env=env,
    )
    assert update.returncode == 0, update.stderr

    rejected = _run_mailbox(
        "write-response",
        "demo",
        "--from",
        "claude-worker",
        "--text",
        "should be rejected while inactive",
        "--request-id",
        "req-codex-claude-003",
        env=env,
    )
    assert rejected.returncode == 1
    assert "response sender not registered or inactive: claude-worker" in rejected.stderr
