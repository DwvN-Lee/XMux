import json
import os
import shutil
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAILBOX = ROOT / "dist" / "bin" / "xmux-mailbox.js"
BRIDGE_RELAY = ROOT / "xmux-bridge.zsh"


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


def _write_fake_tmux(bin_dir: Path, pane_listing: str = "%2"):
    tmux = bin_dir / "tmux"
    tmux.write_text(
        f"""#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-panes)
    printf '%s\\n' '{pane_listing}'
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


def _write_passthrough_tool(bin_dir: Path, name: str, target: str):
    tool = bin_dir / name
    tool.write_text(
        f"""#!/bin/sh
exec "{target}" "$@"
""",
        encoding="utf-8",
    )
    tool.chmod(0o755)
    return tool


def _write_python3_stub(bin_dir: Path):
    stub = bin_dir / "python3"
    stub.write_text(
        """#!/bin/sh
[ -n "$XMUX_PYTHON_STUB_HIT" ] && : > "$XMUX_PYTHON_STUB_HIT"
exit 97
""",
        encoding="utf-8",
    )
    stub.chmod(0o755)
    return stub


def _write_fake_mailbox_cli(install_dir: Path):
    cli = install_dir / "dist" / "bin" / "xmux-mailbox.js"
    cli.parent.mkdir(parents=True, exist_ok=True)
    cli.write_text(
        """#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const command = args[0] || '';
const team = args[1] || '';
const logPath = process.env.XMUX_FAKE_MAILBOX_LOG || '';
if (logPath) fs.appendFileSync(logPath, `${args.join(' ')}\\n`, 'utf8');

const stateDir = path.resolve(process.env.XMUX_STATE_DIR || path.join(process.cwd(), '.codex', 'xmux'));
const teamDir = path.join(stateDir, 'teams', team);

function readJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmpPath, `${JSON.stringify(data, null, 2)}\\n`, 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function getOption(flag) {
  const idx = args.indexOf(flag);
  if (idx < 0 || idx + 1 >= args.length) return '';
  return args[idx + 1];
}

function nowIso() {
  return new Date().toISOString();
}

function entryRequestId(entry) {
  const value = entry.request_id || entry.requestId || '';
  const rawText = Object.prototype.hasOwnProperty.call(entry, 'text')
    ? entry.text
    : (Object.prototype.hasOwnProperty.call(entry, 'message') ? entry.message : '');
  if (value || typeof rawText !== 'string') return value;
  try {
    const nested = JSON.parse(rawText);
    if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
      return nested.request_id || nested.requestId || '';
    }
  } catch (_) {
    return '';
  }
  return '';
}

if (command === 'mark-read') {
  const owner = args[2] || '';
  const timestamp = getOption('--timestamp');
  const requestId = getOption('--request-id');
  const inboxPath = path.join(teamDir, 'inboxes', `${owner}.json`);
  let messages = readJson(inboxPath, []);
  if (!Array.isArray(messages)) messages = [];

  let marked = 0;
  for (const entry of messages) {
    if (!entry || typeof entry !== 'object' || entry.read) continue;
    if (timestamp && entry.timestamp === timestamp) {
      entry.read = true;
    } else if (requestId && entryRequestId(entry) === requestId) {
      entry.read = true;
    } else if (!timestamp && !requestId) {
      entry.read = true;
    } else {
      continue;
    }
    entry.read_at = nowIso();
    marked += 1;
    if (timestamp || requestId) break;
  }
  writeJson(inboxPath, messages);
  process.stdout.write(`${JSON.stringify({ status: 'ok', marked })}\\n`);
  process.exit(0);
}

if (command === 'write-response') {
  const fromName = getOption('--from') || 'unknown-agent';
  const text = getOption('--text');
  const requestId = getOption('--request-id') || '';
  const status = getOption('--status') || 'done';

  const teamCfg = readJson(path.join(teamDir, 'team.json'), {});
  const leadName = (((teamCfg || {}).lead || {}).name) || 'codex-lead';
  const outboxPath = path.join(teamDir, 'inboxes', `${leadName}.json`);
  let messages = readJson(outboxPath, []);
  if (!Array.isArray(messages)) messages = [];

  const entry = {
    id: `rsp-${Date.now()}`,
    type: 'response',
    request_id: requestId || undefined,
    from: fromName,
    to: leadName,
    text,
    timestamp: nowIso(),
    read: false,
    status,
  };
  if (!requestId) delete entry.request_id;
  messages.push(entry);
  writeJson(outboxPath, messages);

  process.stdout.write(`${JSON.stringify({ status, request_id: requestId || null, to: leadName })}\\n`);
  process.exit(0);
}

if (command === 'update-member') {
  const member = args[2] || '';
  const active = getOption('--active');
  const teamPath = path.join(teamDir, 'team.json');
  const cfg = readJson(teamPath, {});
  const members = cfg.members || {};
  if (members[member] && typeof members[member] === 'object') {
    if (active === 'true') members[member].active = true;
    if (active === 'false') members[member].active = false;
    members[member].updated_at = nowIso();
    cfg.members = members;
    writeJson(teamPath, cfg);
  }
  process.stdout.write(`${JSON.stringify({ status: 'ok', member })}\\n`);
  process.exit(0);
}

process.stderr.write(`unsupported command: ${command}\\n`);
process.exit(1);
""",
        encoding="utf-8",
    )
    cli.chmod(0o755)
    return cli


def test_bridge_relay_delivers_codex_request_to_claude_pane_and_marks_read(tmp_path):
    zsh = shutil.which("zsh")
    node = shutil.which("node")
    assert zsh is not None
    assert node is not None
    state_dir = tmp_path / "xmux-state"
    team = "claude-relay-team"
    request_id = "req-claude-relay-001"
    bin_dir = tmp_path / "bin"
    buffer_dir = tmp_path / "buffers"
    install_dir = tmp_path / "install"
    log_path = tmp_path / "tmux.log"
    paste_file = tmp_path / "pasted.txt"
    mailbox_log = tmp_path / "mailbox.log"
    python_hit = tmp_path / "python-hit"
    bin_dir.mkdir()
    buffer_dir.mkdir()
    fake_tmux = _write_fake_tmux(bin_dir)
    _write_passthrough_tool(bin_dir, "node", node)
    _write_passthrough_tool(bin_dir, "grep", "/usr/bin/grep")
    _write_passthrough_tool(bin_dir, "tail", "/usr/bin/tail")
    _write_python3_stub(bin_dir)
    _write_fake_mailbox_cli(install_dir)

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
    _run_mailbox(
        state_dir,
        "enqueue-request",
        team,
        "claude",
        "--from",
        "codex-lead",
        "--message",
        "review the bidirectional dataflow",
        "--request-id",
        request_id,
    )

    inbox = state_dir / "teams" / team / "inboxes" / "claude-worker.json"
    env = os.environ.copy()
    env.update({
        "XMUX_INSTALL_DIR": str(install_dir),
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_TMUX_BIN": str(fake_tmux),
        "XMUX_BRIDGE_PATH": f"{bin_dir}:/bin",
        "XMUX_PYTHON_STUB_HIT": str(python_hit),
        "XMUX_FAKE_MAILBOX_LOG": str(mailbox_log),
        "TMUX_FAKE_LOG": str(log_path),
        "TMUX_FAKE_BUFFER_DIR": str(buffer_dir),
        "TMUX_FAKE_PASTE_FILE": str(paste_file),
    })
    proc = subprocess.Popen(
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
            str(inbox),
            "-d",
            "0",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            pasted = (
                paste_file.read_text(encoding="utf-8")
                if paste_file.exists()
                else ""
            )
            inbox_messages = json.loads(inbox.read_text(encoding="utf-8"))
            if (
                "review the bidirectional dataflow" in pasted
                and inbox_messages[0]["read"] is True
            ):
                break
            time.sleep(0.05)
        else:
            raise AssertionError(
                "bridge relay did not deliver and mark the Claude request"
            )
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)

    pasted = paste_file.read_text(encoding="utf-8")
    assert pasted.startswith(f"[request_id: {request_id}]\n")
    assert "review the bidirectional dataflow" in pasted

    inbox_messages = json.loads(inbox.read_text(encoding="utf-8"))
    assert inbox_messages[0]["read"] is True
    assert inbox_messages[0]["request_id"] == request_id
    assert "mark-read" in mailbox_log.read_text(encoding="utf-8")
    assert not python_hit.exists()


def test_bridge_relay_reports_pane_exit_through_mailbox_cli(tmp_path):
    zsh = shutil.which("zsh")
    node = shutil.which("node")
    assert zsh is not None
    assert node is not None
    state_dir = tmp_path / "xmux-state"
    team = "claude-relay-team"
    bin_dir = tmp_path / "bin"
    buffer_dir = tmp_path / "buffers"
    install_dir = tmp_path / "install"
    log_path = tmp_path / "tmux.log"
    paste_file = tmp_path / "pasted.txt"
    mailbox_log = tmp_path / "mailbox.log"
    python_hit = tmp_path / "python-hit"
    bin_dir.mkdir()
    buffer_dir.mkdir()
    fake_tmux = _write_fake_tmux(bin_dir, pane_listing="%9")
    _write_passthrough_tool(bin_dir, "node", node)
    _write_passthrough_tool(bin_dir, "grep", "/usr/bin/grep")
    _write_passthrough_tool(bin_dir, "tail", "/usr/bin/tail")
    _write_python3_stub(bin_dir)
    _write_fake_mailbox_cli(install_dir)

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

    inbox = state_dir / "teams" / team / "inboxes" / "claude-worker.json"
    outbox = state_dir / "teams" / team / "inboxes" / "codex-lead.json"
    env = os.environ.copy()
    env.update({
        "XMUX_INSTALL_DIR": str(install_dir),
        "XMUX_STATE_DIR": str(state_dir),
        "XMUX_TMUX_BIN": str(fake_tmux),
        "XMUX_BRIDGE_PATH": f"{bin_dir}:/bin",
        "XMUX_PYTHON_STUB_HIT": str(python_hit),
        "XMUX_FAKE_MAILBOX_LOG": str(mailbox_log),
        "TMUX_FAKE_LOG": str(log_path),
        "TMUX_FAKE_BUFFER_DIR": str(buffer_dir),
        "TMUX_FAKE_PASTE_FILE": str(paste_file),
    })
    result = subprocess.run(
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
            str(inbox),
            "-d",
            "0",
        ],
        capture_output=True,
        text=True,
        env=env,
        timeout=5,
    )

    assert result.returncode == 0, result.stderr
    outbox_messages = json.loads(outbox.read_text(encoding="utf-8"))
    assert any(
        msg.get("text") == "claude-worker pane exited."
        for msg in outbox_messages
    )
    assert "write-response" in mailbox_log.read_text(encoding="utf-8")
    assert not python_hit.exists()
