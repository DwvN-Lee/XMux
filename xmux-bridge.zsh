#!/usr/bin/env zsh
# xmux-bridge.zsh
# Provider-neutral XMux inbox relay. It polls a teammate inbox under
# <project>/.codex/xmux/teams/<team>/inboxes/<agent>.json and pastes unread
# messages into the target tmux pane.

set -uo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
_XMUX_BRIDGE_SOURCED_DIR="${${(%):-%x}:A:h}"

if [[ -n "${XMUX_INSTALL_DIR:-}" ]]; then
  XMUX_INSTALL_DIR="${XMUX_INSTALL_DIR:A}"
else
  XMUX_INSTALL_DIR="$_XMUX_BRIDGE_SOURCED_DIR"
fi
export XMUX_INSTALL_DIR

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
    if tmux capture-pane -t "$PANE_ID" -p 2>/dev/null | grep -v '^[[:space:]]*$' | tail -8 | grep -qE "$IDLE_PATTERN"; then
      return 0
    fi
    sleep 1
    (( elapsed++ ))
  done
  echo "[xmux-bridge] warning: idle timeout after ${TIMEOUT}s for $AGENT_NAME" >&2
  return 1
}

read_unread() {
  python3 - "$INBOX" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        msgs = json.load(fh)
except FileNotFoundError:
    print("", end="")
    sys.exit(0)
except json.JSONDecodeError as exc:
    print(f"read_unread: JSON parse error in {path}: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(msgs, list):
    print("", end="")
    sys.exit(0)

for msg in msgs:
    if isinstance(msg, dict) and not msg.get("read", False):
        print(json.dumps(msg, separators=(",", ":")), end="")
        break
PY
}

parse_message() {
  python3 - "$1" <<'PY'
import base64
import json
import sys

msg = json.loads(sys.argv[1])
raw_text = msg.get("text", msg.get("message", ""))
nested = None

if isinstance(raw_text, (dict, list)):
    text = json.dumps(raw_text, separators=(",", ":"))
    if isinstance(raw_text, dict):
        nested = raw_text
elif isinstance(raw_text, str):
    text = raw_text
    try:
        candidate = json.loads(raw_text)
        if isinstance(candidate, dict):
            nested = candidate
    except Exception:
        nested = None
else:
    text = str(raw_text)

request_id = (
    msg.get("request_id")
    or msg.get("requestId")
    or (nested or {}).get("request_id")
    or (nested or {}).get("requestId")
    or ""
)
msg_type = msg.get("type") or (nested or {}).get("type") or ""
fields = [
    base64.b64encode(text.encode("utf-8")).decode("ascii"),
    str(msg.get("timestamp", "")),
    str(msg.get("from", "lead")),
    str(request_id),
    str(msg_type),
]
print("\n".join(fields))
PY
}

decode_b64() {
  python3 - "$1" <<'PY'
import base64
import sys

sys.stdout.write(base64.b64decode(sys.argv[1]).decode("utf-8"))
PY
}

mark_read_inline() {
  python3 - "$INBOX" "$1" "$2" <<'PY'
import json
import os
import tempfile
import sys

path, timestamp, request_id = sys.argv[1:4]

def msg_request_id(msg):
    value = msg.get("request_id") or msg.get("requestId") or ""
    raw_text = msg.get("text", msg.get("message", ""))
    if value or not isinstance(raw_text, str):
        return value
    try:
        nested = json.loads(raw_text)
    except Exception:
        return ""
    if isinstance(nested, dict):
        return nested.get("request_id") or nested.get("requestId") or ""
    return ""

try:
    with open(path, encoding="utf-8") as fh:
        msgs = json.load(fh)
except FileNotFoundError:
    sys.exit(0)

if not isinstance(msgs, list):
    sys.exit(0)

for msg in msgs:
    if not isinstance(msg, dict) or msg.get("read", False):
        continue
    if timestamp and msg.get("timestamp") == timestamp:
        msg["read"] = True
        break
    if request_id and msg_request_id(msg) == request_id:
        msg["read"] = True
        break
    if not timestamp and not request_id:
        msg["read"] = True
        break

dir_name = os.path.dirname(os.path.abspath(path))
os.makedirs(dir_name, exist_ok=True)
with tempfile.NamedTemporaryFile(mode="w", dir=dir_name, delete=False, suffix=".tmp", encoding="utf-8") as fh:
    json.dump(msgs, fh, indent=2)
    fh.write("\n")
    tmp = fh.name
os.replace(tmp, path)
PY
}

mark_read() {
  local timestamp="$1" request_id="$2" script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  if [[ -f "$script" ]]; then
    python3 "$script" mark-read "$TEAM_NAME" "$AGENT_NAME" --timestamp "$timestamp" --request-id "$request_id" >/dev/null 2>&1 && return 0
  fi
  mark_read_inline "$timestamp" "$request_id"
}

append_to_lead() {
  local text="$1" request_id="$2" script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  if [[ -f "$script" ]]; then
    if [[ -n "$request_id" ]]; then
      python3 "$script" write-response "$TEAM_NAME" --from "$AGENT_NAME" --text "$text" --request-id "$request_id" >/dev/null 2>&1 && return 0
    else
      python3 "$script" write-response "$TEAM_NAME" --from "$AGENT_NAME" --text "$text" >/dev/null 2>&1 && return 0
    fi
  fi
  python3 - "$OUTBOX" "$AGENT_NAME" "$1" "$2" <<'PY'
import datetime as dt
import json
import os
import tempfile
import sys

path, agent, text, request_id = sys.argv[1:5]
try:
    with open(path, encoding="utf-8") as fh:
        msgs = json.load(fh)
except Exception:
    msgs = []
if not isinstance(msgs, list):
    msgs = []
entry = {
    "from": agent,
    "text": text,
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "read": False,
}
if request_id:
    entry["request_id"] = request_id
msgs.append(entry)
dir_name = os.path.dirname(os.path.abspath(path))
os.makedirs(dir_name, exist_ok=True)
with tempfile.NamedTemporaryFile(mode="w", dir=dir_name, delete=False, suffix=".tmp", encoding="utf-8") as fh:
    json.dump(msgs, fh, indent=2)
    fh.write("\n")
    tmp = fh.name
os.replace(tmp, path)
PY
}

focus_target_pane() {
  [[ "$PROVIDER" == "copilot" ]] || return 0
  tmux send-keys -t "$PANE_ID" Escape '[' I 2>/dev/null || return 1
  sleep 0.05
}

mark_member_inactive() {
  python3 - "$TEAM_DIR/team.json" "$AGENT_NAME" <<'PY'
import datetime as dt
import json
import os
import sys

path, agent = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(0)
members = cfg.get("members", {})
if not isinstance(members, dict) or agent not in members or not isinstance(members[agent], dict):
    sys.exit(0)
members[agent]["active"] = False
members[agent]["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
changed = True
if not changed:
    sys.exit(0)
tmp = f"{path}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
}

paste_text() {
  local text="$1"
  local text_len=${#text}
  local pos=0
  local chunk_size=300
  local chunk buf

  focus_target_pane || return 1
  tmux send-keys -t "$PANE_ID" C-u 2>/dev/null || return 1
  sleep 0.05

  while (( pos < text_len )); do
    chunk="${text:$pos:$chunk_size}"
    buf="xmux-${$}-${RANDOM}"
    if ! printf '%s' "$chunk" | tmux load-buffer -b "$buf" - 2>/dev/null; then
      echo "[xmux-bridge] error: load-buffer failed for $PANE_ID" >&2
      return 1
    fi
    if ! tmux paste-buffer -d -p -b "$buf" -t "$PANE_ID" 2>/dev/null; then
      tmux delete-buffer -b "$buf" 2>/dev/null
      echo "[xmux-bridge] error: paste-buffer failed for $PANE_ID" >&2
      return 1
    fi
    (( pos += chunk_size ))
    sleep 0.05
  done

  sleep "$SUBMIT_DELAY"
  focus_target_pane || return 1
  buf="xmux-${$}-${RANDOM}"
  if ! printf '\r' | tmux load-buffer -b "$buf" - 2>/dev/null; then
    echo "[xmux-bridge] error: load-buffer failed for submit on $PANE_ID" >&2
    return 1
  fi
  if ! tmux paste-buffer -d -b "$buf" -t "$PANE_ID" 2>/dev/null; then
    tmux delete-buffer -b "$buf" 2>/dev/null
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
  if ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx -- "$PANE_ID"; then
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
      tmux kill-pane -t "$PANE_ID" 2>/dev/null
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
