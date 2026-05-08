import json
import os
import queue
import shutil
import subprocess
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"
LEAD_MCP = ROOT / "xmux-lead-mcp-server.js"
BRIDGE_MCP = ROOT / "bridge-mcp-server.js"
BRIDGE_RELAY = ROOT / "xmux-bridge.zsh"


class McpSession:
    def __init__(self, env):
        self.proc = subprocess.Popen(
            ["node", str(LEAD_MCP)],
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

    def call_tool(self, name, arguments):
        msg_id = self._next_id
        self._next_id += 1
        msg = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        }
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        try:
            line = self._stdout.get(timeout=5)
        except queue.Empty:
            raise AssertionError(f"timed out waiting for {name}")
        response = json.loads(line)
        assert response["id"] == msg_id
        content = response["result"]["content"]
        assert content and content[0]["type"] == "text"
        return json.loads(content[0]["text"])

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


def _write_fake_python(bin_dir: Path, log_path: Path):
    fake = bin_dir / "python3"
    fake.write_text(
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$*\" >> {log_path}\n"
        "exit 127\n",
        encoding="utf-8",
    )
    fake.chmod(0o755)
    python = bin_dir / "python"
    python.write_text(fake.read_text(encoding="utf-8"), encoding="utf-8")
    python.chmod(0o755)
    return fake


def _write_fake_tmux(bin_dir: Path):
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
  send-keys|delete-buffer|kill-pane|capture-pane)
    ;;
  load-buffer)
    buf=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -b)
          buf="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    cat > "$TMUX_FAKE_BUFFER_DIR/$buf"
    ;;
  paste-buffer)
    buf=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -b)
          buf="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    cat "$TMUX_FAKE_BUFFER_DIR/$buf" >> "$TMUX_FAKE_PASTE_FILE"
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)
    return tmux


def _call_bridge_write_to_lead(env, request_id):
    proc = subprocess.Popen(
        ["node", str(BRIDGE_MCP)],
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
                "text": "pong",
                "summary": "pong",
                "request_id": request_id,
            },
        },
    }) + "\n")
    proc.stdin.close()
    response = json.loads(proc.stdout.readline())
    stderr = proc.stderr.read() if proc.stderr is not None else ""
    assert proc.wait(timeout=10) == 0, stderr
    return response["result"]["content"][0]["text"]


def test_codex_claude_ping_pong_dataflow_without_python_runtime(tmp_path):
    assert MAILBOX.exists(), "Node mailbox CLI must exist for Python-free runtime"
    zsh = shutil.which("zsh")
    assert zsh is not None

    state_dir = tmp_path / "xmux-state"
    team = "ping-pong-team"
    request_id = "req-ping-pong-001"
    bin_dir = tmp_path / "bin"
    buffer_dir = tmp_path / "buffers"
    log_path = tmp_path / "tmux.log"
    paste_file = tmp_path / "claude-pane.txt"
    python_log = tmp_path / "python-called.log"
    bin_dir.mkdir()
    buffer_dir.mkdir()
    fake_python = _write_fake_python(bin_dir, python_log)
    fake_tmux = _write_fake_tmux(bin_dir)

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
        "--pane",
        "%2",
    )

    env = os.environ.copy()
    env.update({
        "XMUX_INSTALL_DIR": str(ROOT),
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_TEAM": team,
        "XMUX_AGENT": "claude-worker",
        "XMUX_OUTBOX": str(state_dir / "teams" / team / "inboxes" / "codex-lead.json"),
        "XMUX_TMUX_BIN": str(fake_tmux),
        "PYTHON": str(fake_python),
        "PYTHON3": str(fake_python),
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "TMUX_FAKE_LOG": str(log_path),
        "TMUX_FAKE_BUFFER_DIR": str(buffer_dir),
        "TMUX_FAKE_PASTE_FILE": str(paste_file),
    })

    session = McpSession(env)
    relay = subprocess.Popen(
        [
            zsh,
            str(BRIDGE_RELAY),
            "-p",
            "%2",
            "-T",
            team,
            "-a",
            "claude-worker",
            "-P",
            "claude",
            "-i",
            str(state_dir / "teams" / team / "inboxes" / "claude-worker.json"),
            "-d",
            "0",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        sent = session.call_tool(
            "send_to_teammate",
            {
                "team": team,
                "to": "claude",
                "message": "ping test",
                "request_id": request_id,
            },
        )
        assert sent == {
            "status": "pending",
            "request_id": request_id,
            "to": "claude-worker",
        }

        deadline = time.time() + 5
        while time.time() < deadline:
            pasted = (
                paste_file.read_text(encoding="utf-8")
                if paste_file.exists()
                else ""
            )
            if "[request_id: req-ping-pong-001]\nping test" in pasted:
                break
            time.sleep(0.05)
        else:
            raise AssertionError("Claude pane did not receive ping test")

        bridge_result = _call_bridge_write_to_lead(env, request_id)
        assert bridge_result == "ok: response delivered to lead"

        pong = session.call_tool(
            "wait_teammate_response",
            {
                "team": team,
                "request_id": request_id,
                "timeout_sec": 1,
                "interval_sec": 0.01,
                "mark_read": True,
            },
        )
        assert pong["status"] == "done"
        assert pong["response"]["from"] == "claude-worker"
        assert pong["response"]["text"] == "pong"
        assert pong["marked_read"] == 1
        assert not python_log.exists(), python_log.read_text(encoding="utf-8")
    finally:
        relay.terminate()
        try:
            relay.wait(timeout=5)
        except subprocess.TimeoutExpired:
            relay.kill()
            relay.wait(timeout=5)
        session.close()
