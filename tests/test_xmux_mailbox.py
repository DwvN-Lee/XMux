import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"


def _run_mailbox(*args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["node", str(MAILBOX), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )


def _mailbox_json(*args: str, env: dict | None = None):
    result = _run_mailbox(*args, env=env)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def _node_eval(script: str, env: dict | None = None) -> str:
    result = subprocess.run(
        ["node", "-e", script],
        env=env,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_store_root_defaults_to_project_local_codex_xmux(monkeypatch):
    monkeypatch.delenv("XMUX_STATE_DIR", raising=False)
    monkeypatch.delenv("XMUX_PROJECT_DIR", raising=False)
    monkeypatch.chdir(ROOT)

    payload = _node_eval(
        "const m=require('./src/mailbox/core');"
        "console.log(JSON.stringify({root:m.storeRoot(), team:m.teamDir('demo')}));"
    )
    data = json.loads(payload)
    assert Path(data["root"]) == ROOT / ".codex" / "xmux"
    assert Path(data["team"]) == ROOT / ".codex" / "xmux" / "teams" / "demo"


def test_store_root_prefers_state_dir(tmp_path, monkeypatch):
    state_dir = tmp_path / "state"
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)

    payload = _node_eval(
        "const m=require('./src/mailbox/core');"
        "console.log(JSON.stringify({root:m.storeRoot(), team:m.teamDir('demo')}));",
        env=env,
    )
    data = json.loads(payload)
    assert Path(data["root"]) == state_dir
    assert Path(data["team"]) == state_dir / "teams" / "demo"


def test_store_root_uses_project_dir_when_state_dir_absent(tmp_path, monkeypatch):
    project_dir = tmp_path / "project"
    env = os.environ.copy()
    env.pop("XMUX_STATE_DIR", None)
    env["XMUX_PROJECT_DIR"] = str(project_dir)

    payload = _node_eval(
        "const m=require('./src/mailbox/core'); console.log(m.storeRoot());",
        env=env,
    )
    assert Path(payload) == project_dir / ".codex" / "xmux"


def test_init_and_register_member(tmp_path, monkeypatch):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")

    init = _mailbox_json(
        "init-team",
        "demo",
        "--lead-name",
        "codex-lead",
        "--lead-provider",
        "codex",
        "--lead-pane",
        "%1",
        env=env,
    )
    registered = _mailbox_json(
        "register-member",
        "demo",
        "worker-a",
        "--provider",
        "gemini",
        "--pane",
        "%2",
        env=env,
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
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)
    _mailbox_json("register-member", "demo", "worker-a", "--provider", "gemini", "--pane", "%2", env=env)

    result = _mailbox_json(
        "update-member",
        "demo",
        "worker-a",
        "--session",
        "xmux-demo-worker-a",
        "--display-mode",
        "virtual",
        "--active",
        "false",
        env=env,
    )

    member = result["member"]
    assert member["session"] == "xmux-demo-worker-a"
    assert member["display_mode"] == "virtual"
    assert member["active"] is False


def test_register_member_rejects_codex_teammate(tmp_path, monkeypatch):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)

    result = _run_mailbox("register-member", "demo", "worker-a", "--provider", "codex", env=env)
    assert result.returncode == 1
    assert "teammate provider" in result.stderr


def test_enqueue_request_format_includes_request_id_in_teammate_inbox(
    tmp_path, monkeypatch
):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)
    _mailbox_json("register-member", "demo", "worker-a", "--provider", "gemini", env=env)

    result = _mailbox_json(
        "enqueue-request",
        "demo",
        "worker-a",
        "--from",
        "codex-lead",
        "--message",
        "inspect the failing test",
        "--request-id",
        "req-001",
        env=env,
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
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)
    _mailbox_json("register-member", "demo", "gemini-worker", "--provider", "gemini", env=env)

    result = _mailbox_json(
        "enqueue-request",
        "demo",
        "gemini",
        "--from",
        "codex-lead",
        "--message",
        "provider alias should resolve",
        "--request-id",
        "req-provider-alias",
        env=env,
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
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)

    result = _run_mailbox(
        "enqueue-request",
        "demo",
        "gemini",
        "--from",
        "codex-lead",
        "--message",
        "should fail before creating an orphan inbox",
        "--request-id",
        "req-missing-teammate",
        env=env,
    )
    assert result.returncode == 1
    assert "teammate not registered or inactive: gemini" in result.stderr

    team_dir = tmp_path / ".xmux" / "teams" / "demo"
    assert not (team_dir / "inboxes" / "gemini.json").exists()
    assert not (team_dir / "requests" / "req-missing-teammate.json").exists()


def test_write_and_read_response_correlation(tmp_path, monkeypatch):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)
    _mailbox_json("register-member", "demo", "worker-a", "--provider", "gemini", env=env)
    _mailbox_json(
        "enqueue-request",
        "demo",
        "worker-a",
        "--from",
        "codex-lead",
        "--message",
        "summarize status",
        "--request-id",
        "req-002",
        env=env,
    )

    written = _mailbox_json(
        "write-response",
        "demo",
        "--from",
        "worker-a",
        "--text",
        "done with notes",
        "--summary",
        "done",
        "--request-id",
        "req-002",
        env=env,
    )
    read = _mailbox_json("read-response", "demo", "req-002", "--mark-read", env=env)

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


def test_write_response_rejects_unregistered_teammate_source(tmp_path, monkeypatch):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)

    result = _run_mailbox(
        "write-response",
        "demo",
        "--from",
        "claude-worker",
        "--text",
        "unregistered sender must not reach lead",
        "--request-id",
        "req-spoofed-source",
        env=env,
    )
    assert result.returncode == 1
    assert "response sender not registered or inactive: claude-worker" in result.stderr

    team_dir = tmp_path / ".xmux" / "teams" / "demo"
    assert json.loads((team_dir / "inboxes" / "codex-lead.json").read_text()) == []
    assert not (team_dir / "requests" / "req-spoofed-source.json").exists()


def test_wait_response_timeout_returns_pending(tmp_path, monkeypatch):
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(tmp_path / ".xmux")
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)
    _mailbox_json("register-member", "demo", "worker-a", "--provider", "gemini", env=env)
    _mailbox_json(
        "enqueue-request",
        "demo",
        "worker-a",
        "--from",
        "codex-lead",
        "--message",
        "take your time",
        "--request-id",
        "req-timeout",
        env=env,
    )

    result = _mailbox_json(
        "wait-response",
        "demo",
        "req-timeout",
        "--timeout",
        "0.01",
        "--interval",
        "0.001",
        env=env,
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
    env = os.environ.copy()
    env["XMUX_STATE_DIR"] = str(state_dir)
    _mailbox_json("init-team", "demo", "--lead-name", "codex-lead", "--lead-provider", "codex", env=env)
    _mailbox_json("register-member", "demo", "worker-a", "--provider", "gemini", env=env)
    _mailbox_json("register-member", "demo", "worker-b", "--provider", "copilot", env=env)

    procs = []
    for worker, text in [("worker-a", "first"), ("worker-b", "second")]:
        procs.append(
            subprocess.Popen(
                [
                    "node",
                    str(MAILBOX),
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
