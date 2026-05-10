#!/usr/bin/env zsh
# runtime/relay/xmux-bridge.zsh
# Provider-neutral XMux inbox relay. It polls a teammate inbox under
# <project>/.codex/xmux/teams/<team>/inboxes/<agent>.json and pastes unread
# messages into the target tmux pane.

set -uo pipefail

if [[ -n "${XMUX_BRIDGE_PATH:-}" ]]; then
  PATH="$XMUX_BRIDGE_PATH"
else
  PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
fi
_XMUX_BRIDGE_SOURCED_DIR="${${(%):-%x}:A:h}"
_XMUX_BRIDGE_INSTALL_DIR="$_XMUX_BRIDGE_SOURCED_DIR"
if [[ "${_XMUX_BRIDGE_INSTALL_DIR:t}" == "relay" && "${_XMUX_BRIDGE_INSTALL_DIR:h:t}" == "runtime" ]]; then
  _XMUX_BRIDGE_INSTALL_DIR="${_XMUX_BRIDGE_INSTALL_DIR:h:h}"
fi
TMUX_BIN="${XMUX_TMUX_BIN:-tmux}"
NODE_BIN="${XMUX_NODE_BIN:-node}"

_xmux_tmux() {
  command "$TMUX_BIN" "$@"
}

if [[ -n "${XMUX_INSTALL_DIR:-}" ]]; then
  XMUX_INSTALL_DIR="${XMUX_INSTALL_DIR:A}"
else
  XMUX_INSTALL_DIR="$_XMUX_BRIDGE_INSTALL_DIR"
fi
export XMUX_INSTALL_DIR
XMUX_MCP_PACKAGE_SPEC="${XMUX_MCP_PACKAGE_SPEC:-xmux-bridge}"
XMUX_MCP_NPX_PREFIX="${XMUX_MCP_NPX_PREFIX:-$HOME/.cache/xmux/npm-prefix}"

_xmux_node() {
  command "$NODE_BIN" "$@"
}

_xmux_package_name_from_spec() {
  local spec="$1" rest scope package_name
  if [[ "$spec" == @* ]]; then
    rest="${spec#@}"
    scope="${rest%%/*}"
    package_name="${rest#*/}"
    package_name="${package_name%%@*}"
    print -r -- "@${scope}/${package_name}"
  else
    print -r -- "${spec%%@*}"
  fi
}

_xmux_cached_package_root() {
  print -r -- "$XMUX_MCP_NPX_PREFIX/node_modules/$(_xmux_package_name_from_spec "$XMUX_MCP_PACKAGE_SPEC")"
}

_xmux_mailbox_cli() {
  local bin_path script_path
  bin_path="$XMUX_MCP_NPX_PREFIX/node_modules/.bin/xmux-mailbox"
  if [[ -x "$bin_path" || -f "$bin_path" ]]; then
    command "$bin_path" "$@"
    return
  fi
  for script_path in \
      "${XMUX_MAILBOX_NODE_CLI:-}" \
      "$(_xmux_cached_package_root)/dist/bin/xmux-mailbox.js" \
      "$XMUX_INSTALL_DIR/dist/bin/xmux-mailbox.js"; do
    [[ -n "$script_path" && -f "$script_path" ]] || continue
    _xmux_node "$script_path" "$@"
    return
  done
  command -v npx >/dev/null 2>&1 || return 127
  npx --prefix "$XMUX_MCP_NPX_PREFIX" xmux-mailbox "$@"
}

_xmux_bridge_project_root() {
  local dir="${1:-$PWD}"
  dir="${dir:A}"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -e "$dir/.git" ]]; then
      print -r -- "$dir"
      return
    fi
    dir="${dir:h}"
  done
  print -r -- "${1:-$PWD}"
}

if [[ -n "${XMUX_PROJECT_DIR:-}" ]]; then
  XMUX_PROJECT_DIR="${XMUX_PROJECT_DIR:A}"
else
  XMUX_PROJECT_DIR="$(_xmux_bridge_project_root "$PWD")"
fi
export XMUX_PROJECT_DIR

if [[ -n "${XMUX_STATE_DIR:-}" ]]; then
  XMUX_STATE_DIR="${XMUX_STATE_DIR:A}"
else
  XMUX_STATE_DIR="$XMUX_PROJECT_DIR/.codex/xmux"
fi
export XMUX_STATE_DIR
unset XMUX_DIR XMUX_HOME 2>/dev/null || true

XMUX_LEAD_AGENT="${XMUX_LEAD_AGENT:-codex-lead}"

PANE_ID=""
TEAM_NAME=""
AGENT_NAME=""
PROVIDER=""
INBOX=""
TIMEOUT=60
IDLE_PATTERN=""
POLL_INTERVAL=0.5
SUBMIT_DELAY="${XMUX_SUBMIT_DELAY:-0.2}"

while getopts "p:T:a:i:x:w:d:P:" opt; do
  case "$opt" in
    p) PANE_ID="$OPTARG" ;;
    T) TEAM_NAME="$OPTARG" ;;
    a) AGENT_NAME="$OPTARG" ;;
    P) PROVIDER="$OPTARG" ;;
    i) INBOX="$OPTARG" ;;
    x) TIMEOUT="$OPTARG" ;;
    w) IDLE_PATTERN="$OPTARG" ;;
    d) SUBMIT_DELAY="$OPTARG" ;;
    *) echo "Usage: $0 -p <pane_id> -T <team> -a <agent> [-P <provider>] [-i <inbox>] [-x <timeout>] [-w <idle_pattern>] [-d <submit_delay>]" >&2; exit 1 ;;
  esac
done

[[ -n "$PANE_ID" ]] || { echo "error: -p <pane_id> required" >&2; exit 1; }
[[ -n "$TEAM_NAME" ]] || { echo "error: -T <team> required" >&2; exit 1; }
[[ -n "$AGENT_NAME" ]] || { echo "error: -a <agent> required" >&2; exit 1; }

TEAM_DIR="$XMUX_STATE_DIR/teams/$TEAM_NAME"
INBOX_DIR="$TEAM_DIR/inboxes"
BRIDGE_PID_FILE="$TEAM_DIR/.${AGENT_NAME}-bridge.pid"
BRIDGE_ENV_FILE="$TEAM_DIR/.bridge-${AGENT_NAME}.env"
[[ -n "$INBOX" ]] || INBOX="$INBOX_DIR/$AGENT_NAME.json"
OUTBOX="$INBOX_DIR/$XMUX_LEAD_AGENT.json"

mkdir -p "$INBOX_DIR"
[[ -f "$INBOX" ]] || print -r -- '[]' > "$INBOX"
[[ -f "$OUTBOX" ]] || print -r -- '[]' > "$OUTBOX"

wait_for_idle() {
  [[ -z "$IDLE_PATTERN" ]] && return 0
  local elapsed=0
  while (( elapsed < TIMEOUT )); do
    if _xmux_tmux capture-pane -t "$PANE_ID" -p 2>/dev/null | grep -v '^[[:space:]]*$' | tail -8 | grep -qE "$IDLE_PATTERN"; then
      return 0
    fi
    sleep 1
    (( elapsed++ ))
  done
  echo "[xmux-bridge] warning: idle timeout after ${TIMEOUT}s for $AGENT_NAME" >&2
  return 1
}

read_unread() {
  _xmux_node - "$INBOX" <<'NODE'
const fs = require('fs');

const inboxPath = process.argv[2];
let raw = '';
try {
  raw = fs.readFileSync(inboxPath, 'utf8');
} catch (error) {
  if (error && error.code === 'ENOENT') {
    process.stdout.write('');
    process.exit(0);
  }
  throw error;
}

let messages;
try {
  messages = JSON.parse(raw);
} catch (error) {
  const detail = error && error.message ? error.message : String(error);
  console.error(`read_unread: JSON parse error in ${inboxPath}: ${detail}`);
  process.exit(1);
}

if (!Array.isArray(messages)) {
  process.stdout.write('');
  process.exit(0);
}

for (const message of messages) {
  if (message && typeof message === 'object' && !message.read) {
    process.stdout.write(JSON.stringify(message));
    break;
  }
}
NODE
}

parse_message() {
  _xmux_node - "$1" <<'NODE'
const message = JSON.parse(process.argv[2] || '{}');

const hasText = Object.prototype.hasOwnProperty.call(message, 'text');
const hasMessage = Object.prototype.hasOwnProperty.call(message, 'message');
const rawText = hasText ? message.text : (hasMessage ? message.message : '');
let nested = null;
let text = '';

if (rawText && typeof rawText === 'object') {
  text = JSON.stringify(rawText);
  if (!Array.isArray(rawText)) nested = rawText;
} else if (typeof rawText === 'string') {
  text = rawText;
  try {
    const candidate = JSON.parse(rawText);
    if (candidate && typeof candidate === 'object' && !Array.isArray(candidate)) {
      nested = candidate;
    }
  } catch (_) {
    nested = null;
  }
} else {
  text = String(rawText ?? '');
}

const requestId =
  message.request_id ||
  message.requestId ||
  ((nested || {}).request_id || (nested || {}).requestId) ||
  '';
const messageType = message.type || (nested || {}).type || '';
const fields = [
  Buffer.from(text, 'utf8').toString('base64'),
  String(message.timestamp ?? ''),
  String(message.from ?? 'lead'),
  String(requestId),
  String(messageType),
];
process.stdout.write(fields.join('\n'));
NODE
}

decode_b64() {
  _xmux_node - "$1" <<'NODE'
const encoded = process.argv[2] || '';
if (!encoded) process.exit(0);
process.stdout.write(Buffer.from(encoded, 'base64').toString('utf8'));
NODE
}

mark_read_inline() {
  _xmux_node - "$INBOX" "$1" "$2" <<'NODE'
const fs = require('fs');
const path = require('path');

const inboxPath = process.argv[2];
const timestamp = process.argv[3] || '';
const requestId = process.argv[4] || '';

function entryRequestId(entry) {
  const direct = entry.request_id || entry.requestId || '';
  const rawText = Object.prototype.hasOwnProperty.call(entry, 'text')
    ? entry.text
    : (Object.prototype.hasOwnProperty.call(entry, 'message') ? entry.message : '');
  if (direct || typeof rawText !== 'string') return direct;
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

let messages;
try {
  messages = JSON.parse(fs.readFileSync(inboxPath, 'utf8'));
} catch (error) {
  if (error && error.code === 'ENOENT') process.exit(0);
  throw error;
}

if (!Array.isArray(messages)) process.exit(0);

for (const message of messages) {
  if (!message || typeof message !== 'object' || message.read) continue;
  if (timestamp && message.timestamp === timestamp) {
    message.read = true;
    break;
  }
  if (requestId && entryRequestId(message) === requestId) {
    message.read = true;
    break;
  }
  if (!timestamp && !requestId) {
    message.read = true;
    break;
  }
}

const resolved = path.resolve(inboxPath);
const dirName = path.dirname(resolved);
fs.mkdirSync(dirName, { recursive: true });
const tmpPath = path.join(
  dirName,
  `.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`,
);
fs.writeFileSync(tmpPath, `${JSON.stringify(messages, null, 2)}\n`, 'utf8');
fs.renameSync(tmpPath, resolved);
NODE
}

mark_read() {
  local timestamp="$1" request_id="$2"
  _xmux_mailbox_cli mark-read "$TEAM_NAME" "$AGENT_NAME" --timestamp "$timestamp" --request-id "$request_id" >/dev/null 2>&1 && return 0
  mark_read_inline "$timestamp" "$request_id"
}

append_to_lead_inline() {
  _xmux_node - "$OUTBOX" "$AGENT_NAME" "$1" "$2" <<'NODE'
const fs = require('fs');
const path = require('path');

const outboxPath = process.argv[2];
const agent = process.argv[3];
const text = process.argv[4];
const requestId = process.argv[5];
let messages = [];

try {
  messages = JSON.parse(fs.readFileSync(outboxPath, 'utf8'));
} catch (_) {
  messages = [];
}
if (!Array.isArray(messages)) messages = [];

const entry = {
  from: agent,
  text,
  timestamp: new Date().toISOString(),
  read: false,
};
if (requestId) entry.request_id = requestId;
messages.push(entry);

const resolved = path.resolve(outboxPath);
const dirName = path.dirname(resolved);
fs.mkdirSync(dirName, { recursive: true });
const tmpPath = path.join(
  dirName,
  `.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`,
);
fs.writeFileSync(tmpPath, `${JSON.stringify(messages, null, 2)}\n`, 'utf8');
fs.renameSync(tmpPath, resolved);
NODE
}

append_to_lead() {
  local text="$1" request_id="$2"
  if [[ -n "$request_id" ]]; then
    _xmux_mailbox_cli write-response "$TEAM_NAME" --from "$AGENT_NAME" --text "$text" --request-id "$request_id" >/dev/null 2>&1 && return 0
  else
    _xmux_mailbox_cli write-response "$TEAM_NAME" --from "$AGENT_NAME" --text "$text" >/dev/null 2>&1 && return 0
  fi
  append_to_lead_inline "$text" "$request_id"
}

focus_target_pane() {
  [[ "$PROVIDER" == "copilot" ]] || return 0
  _xmux_tmux send-keys -t "$PANE_ID" Escape '[' I 2>/dev/null || return 1
  sleep 0.05
}

mark_member_inactive() {
  _xmux_mailbox_cli update-member "$TEAM_NAME" "$AGENT_NAME" --active false >/dev/null 2>&1 && return 0
  _xmux_node - "$TEAM_DIR/team.json" "$AGENT_NAME" <<'NODE'
const fs = require('fs');

const teamPath = process.argv[2];
const agentName = process.argv[3];
let config;
try {
  config = JSON.parse(fs.readFileSync(teamPath, 'utf8'));
} catch (_) {
  process.exit(0);
}

const members = config.members;
if (!members || typeof members !== 'object' || !members[agentName] || typeof members[agentName] !== 'object') {
  process.exit(0);
}

members[agentName].active = false;
members[agentName].updated_at = new Date().toISOString();
const tmpPath = `${teamPath}.tmp`;
fs.writeFileSync(tmpPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
fs.renameSync(tmpPath, teamPath);
NODE
}

paste_text() {
  local text="$1"
  local text_len=${#text}
  local pos=0
  local chunk_size=300
  local chunk buf

  focus_target_pane || return 1
  _xmux_tmux send-keys -t "$PANE_ID" C-u 2>/dev/null || return 1
  sleep 0.05

  while (( pos < text_len )); do
    chunk="${text:$pos:$chunk_size}"
    buf="xmux-${$}-${RANDOM}"
    if ! printf '%s' "$chunk" | _xmux_tmux load-buffer -b "$buf" - 2>/dev/null; then
      echo "[xmux-bridge] error: load-buffer failed for $PANE_ID" >&2
      return 1
    fi
    if ! _xmux_tmux paste-buffer -d -p -b "$buf" -t "$PANE_ID" 2>/dev/null; then
      _xmux_tmux delete-buffer -b "$buf" 2>/dev/null
      echo "[xmux-bridge] error: paste-buffer failed for $PANE_ID" >&2
      return 1
    fi
    (( pos += chunk_size ))
    sleep 0.05
  done

  sleep "$SUBMIT_DELAY"
  focus_target_pane || return 1
  buf="xmux-${$}-${RANDOM}"
  if ! printf '\r' | _xmux_tmux load-buffer -b "$buf" - 2>/dev/null; then
    echo "[xmux-bridge] error: load-buffer failed for submit on $PANE_ID" >&2
    return 1
  fi
  if ! _xmux_tmux paste-buffer -d -b "$buf" -t "$PANE_ID" 2>/dev/null; then
    _xmux_tmux delete-buffer -b "$buf" 2>/dev/null
    echo "[xmux-bridge] error: paste-buffer submit failed for $PANE_ID" >&2
    return 1
  fi
}

cleanup() {
  local recorded_pid=""
  [[ -f "$BRIDGE_PID_FILE" ]] && recorded_pid="$(< "$BRIDGE_PID_FILE")"
  if [[ "$recorded_pid" == "$$" ]]; then
    rm -f "$BRIDGE_PID_FILE"
    rm -f "$BRIDGE_ENV_FILE"
    mark_member_inactive
  fi
}
trap 'cleanup; exit 0' INT TERM EXIT

echo "[xmux-bridge] started - pane:$PANE_ID agent:$AGENT_NAME team:$TEAM_NAME"

defer_count=0
while true; do
  if ! _xmux_tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx -- "$PANE_ID"; then
    append_to_lead "$AGENT_NAME pane exited." ""
    exit 0
  fi

  msg="$(read_unread || true)"
  if [[ -n "$msg" ]]; then
    parsed="$(parse_message "$msg" 2>/dev/null || true)"
    if [[ -z "$parsed" ]]; then
      echo "[xmux-bridge] warning: failed to parse unread message for $AGENT_NAME" >&2
      sleep 2
      continue
    fi

    fields=("${(@f)parsed}")
    text="$(decode_b64 "${fields[1]:-}")"
    timestamp="${fields[2]:-}"
    from_agent="${fields[3]:-lead}"
    request_id="${fields[4]:-}"
    msg_type="${fields[5]:-}"

    if [[ "$msg_type" == "shutdown_request" ]]; then
      mark_read "$timestamp" "$request_id"
      if [[ -n "$request_id" ]]; then
        append_to_lead "{\"type\":\"shutdown_approved\",\"from\":\"$AGENT_NAME\",\"request_id\":\"$request_id\"}" "$request_id"
      else
        append_to_lead "{\"type\":\"shutdown_approved\",\"from\":\"$AGENT_NAME\"}" ""
      fi
      _xmux_tmux kill-pane -t "$PANE_ID" 2>/dev/null
      exit 0
    fi

    if [[ -n "$request_id" ]]; then
      text="[request_id: $request_id]
$text"
    fi

    if (( ${#text} > 120 )); then
      echo "[xmux-bridge] delivering from '$from_agent' to '$AGENT_NAME' (${#text} chars)"
    else
      echo "[xmux-bridge] delivering from '$from_agent' to '$AGENT_NAME': $text"
    fi

    if ! wait_for_idle; then
      (( defer_count++ ))
      echo "[xmux-bridge] warning: $AGENT_NAME not idle, deferring (${defer_count})" >&2
      sleep 3
      continue
    fi
    defer_count=0

    if paste_text "$text"; then
      mark_read "$timestamp" "$request_id"
    else
      sleep 2
      continue
    fi
  fi

  sleep "$POLL_INTERVAL"
done
