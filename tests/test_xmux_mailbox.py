import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import xmux_mailbox


def test_store_root_defaults_to_project_local_codex_xmux(monkeypatch):
    project = Path(__file__).resolve().parent.parent
    monkeypatch.delenv("XMUX_STATE_DIR", raising=False)
    monkeypatch.delenv("XMUX_PROJECT_DIR", raising=False)
    monkeypatch.chdir(project)

    assert xmux_mailbox.store_root() == project / ".codex" / "xmux"
    assert xmux_mailbox.team_dir("demo") == project / ".codex" / "xmux" / "teams" / "demo"


def test_store_root_prefers_state_dir(tmp_path, monkeypatch):
    state_dir = tmp_path / "state"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))

    assert xmux_mailbox.store_root() == state_dir
    assert xmux_mailbox.team_dir("demo") == state_dir / "teams" / "demo"


def test_store_root_uses_project_dir_when_state_dir_absent(tmp_path, monkeypatch):
    project_dir = tmp_path / "project"
    monkeypatch.delenv("XMUX_STATE_DIR", raising=False)
    monkeypatch.setenv("XMUX_PROJECT_DIR", str(project_dir))

    assert xmux_mailbox.store_root() == project_dir / ".codex" / "xmux"


def test_init_and_register_member(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))

    init = xmux_mailbox.init_team(
        "demo",
        lead_name="codex-lead",
        lead_provider="codex",
        lead_pane="%1",
    )
    registered = xmux_mailbox.register_member(
        "demo",
        "worker-a",
        provider="gemini",
        pane="%2",
    )

    team_dir = tmp_path / ".xmux" / "teams" / "demo"
    assert init["status"] == "ok"
    assert registered["status"] == "ok"
    assert (team_dir / "team.json").is_file()
    assert (team_dir / "inboxes").is_dir()
    assert (team_dir / "requests").is_dir()
    assert (team_dir / "events.jsonl").is_file()

    cfg = json.loads((team_dir / "team.json").read_text())
    assert cfg["lead"]["name"] == "codex-lead"
    assert cfg["lead"]["provider"] == "codex"
    assert cfg["members"]["worker-a"]["provider"] == "gemini"
    assert cfg["members"]["worker-a"]["backend"] == "tmux"
    assert cfg["members"]["worker-a"]["pane"] == "%2"
    assert json.loads((team_dir / "inboxes" / "codex-lead.json").read_text()) == []
    assert json.loads((team_dir / "inboxes" / "worker-a.json").read_text()) == []


def test_update_member_runtime_state(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")
    xmux_mailbox.register_member("demo", "worker-a", provider="gemini", pane="%2")

    result = xmux_mailbox.update_member(
        "demo",
        "worker-a",
        session="xmux-demo-worker-a",
        display_mode="virtual",
        active=False,
    )

    member = result["member"]
    assert member["session"] == "xmux-demo-worker-a"
    assert member["display_mode"] == "virtual"
    assert member["active"] is False


def test_register_member_rejects_codex_teammate(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")

    with pytest.raises(xmux_mailbox.MailboxError, match="teammate provider"):
        xmux_mailbox.register_member("demo", "worker-a", "codex")


def test_enqueue_request_format_includes_request_id_in_teammate_inbox(
    tmp_path, monkeypatch
):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")
    xmux_mailbox.register_member("demo", "worker-a", "gemini")

    result = xmux_mailbox.enqueue_request(
        "demo",
        "worker-a",
        from_name="codex-lead",
        message="inspect the failing test",
        request_id="req-001",
    )

    assert result == {"status": "pending", "request_id": "req-001", "to": "worker-a"}
    team_dir = tmp_path / ".xmux" / "teams" / "demo"
    inbox = json.loads((team_dir / "inboxes" / "worker-a.json").read_text())
    assert len(inbox) == 1
    assert inbox[0]["type"] == "request"
    assert inbox[0]["request_id"] == "req-001"
    assert inbox[0]["from"] == "codex-lead"
    assert inbox[0]["to"] == "worker-a"
    assert inbox[0]["text"] == "inspect the failing test"
    assert inbox[0]["read"] is False

    req = json.loads((team_dir / "requests" / "req-001.json").read_text())
    assert req["request_id"] == "req-001"
    assert req["status"] == "pending"
    assert req["responses"] == []


def test_enqueue_request_resolves_active_provider_alias(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")
    xmux_mailbox.register_member("demo", "gemini-worker", "gemini")

    result = xmux_mailbox.enqueue_request(
        "demo",
        "gemini",
        from_name="codex-lead",
        message="provider alias should resolve",
        request_id="req-provider-alias",
    )

    assert result == {
        "status": "pending",
        "request_id": "req-provider-alias",
        "to": "gemini-worker",
    }
    team_dir = tmp_path / ".xmux" / "teams" / "demo"
    assert (team_dir / "inboxes" / "gemini-worker.json").is_file()
    assert not (team_dir / "inboxes" / "gemini.json").exists()


def test_enqueue_request_rejects_unknown_teammate(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")

    with pytest.raises(
        xmux_mailbox.MailboxError,
        match="teammate not registered or inactive: gemini",
    ):
        xmux_mailbox.enqueue_request(
            "demo",
            "gemini",
            from_name="codex-lead",
            message="should fail before creating an orphan inbox",
            request_id="req-missing-teammate",
        )

    team_dir = tmp_path / ".xmux" / "teams" / "demo"
    assert not (team_dir / "inboxes" / "gemini.json").exists()
    assert not (team_dir / "requests" / "req-missing-teammate.json").exists()


def test_write_and_read_response_correlation(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")
    xmux_mailbox.register_member("demo", "worker-a", "gemini")
    xmux_mailbox.enqueue_request(
        "demo",
        "worker-a",
        from_name="codex-lead",
        message="summarize status",
        request_id="req-002",
    )

    written = xmux_mailbox.write_response(
        "demo",
        from_name="worker-a",
        text="done with notes",
        summary="done",
        request_id="req-002",
    )
    read = xmux_mailbox.read_response("demo", "req-002", mark_read=True)

    assert written["status"] == "done"
    assert written["request_id"] == "req-002"
    assert read["status"] == "done"
    assert read["response"]["request_id"] == "req-002"
    assert read["response"]["from"] == "worker-a"
    assert read["response"]["text"] == "done with notes"
    assert read["response"]["summary"] == "done"
    assert read["marked_read"] == 1

    lead_inbox = json.loads(
        (tmp_path / ".xmux" / "teams" / "demo" / "inboxes" / "codex-lead.json")
        .read_text()
    )
    assert lead_inbox[0]["request_id"] == "req-002"
    assert lead_inbox[0]["read"] is True


def test_wait_response_timeout_returns_pending(tmp_path, monkeypatch):
    monkeypatch.setenv("XMUX_STATE_DIR", str(tmp_path / ".xmux"))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")
    xmux_mailbox.register_member("demo", "worker-a", "gemini")
    xmux_mailbox.enqueue_request(
        "demo",
        "worker-a",
        from_name="codex-lead",
        message="take your time",
        request_id="req-timeout",
    )

    result = xmux_mailbox.wait_response(
        "demo",
        "req-timeout",
        timeout=0.01,
        interval=0.001,
    )

    assert result == {
        "status": "pending",
        "request_id": "req-timeout",
        "timed_out": True,
    }


def test_concurrent_response_writes_preserve_both_lead_inbox_entries(
    tmp_path, monkeypatch
):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex")
    xmux_mailbox.register_member("demo", "worker-a", "gemini")
    xmux_mailbox.register_member("demo", "worker-b", "copilot")

    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)
    procs = []
    for worker, text in [("worker-a", "first"), ("worker-b", "second")]:
        procs.append(
            subprocess.Popen(
                [
                    sys.executable,
                    str(SCRIPTS / "xmux_mailbox.py"),
                    "write-response",
                    "demo",
                    "--from",
                    worker,
                    "--text",
                    text,
                ],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        )

    outputs = []
    for proc in procs:
        out, err = proc.communicate(timeout=10)
        assert proc.returncode == 0, err
        outputs.append(json.loads(out))

    assert {out["status"] for out in outputs} == {"done"}
    lead_inbox = json.loads(
        (state_dir / "teams" / "demo" / "inboxes" / "codex-lead.json").read_text()
    )
    assert len(lead_inbox) == 2
    assert {entry["from"] for entry in lead_inbox} == {"worker-a", "worker-b"}
    assert {entry["text"] for entry in lead_inbox} == {"first", "second"}
