# xmux.zsh - Codex-led XMux shell layer.
#
# Source this file from zsh, then run:
#   xmux -T <team> [--claude] [--gemini] [--copilot] [codex args...]

if [[ -n "$ZSH_VERSION" ]]; then
  _XMUX_SOURCED_DIR="${${(%):-%x}:A:h}"
else
  _XMUX_SOURCED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

if [[ -n "${XMUX_INSTALL_DIR+x}" && -n "${XMUX_INSTALL_DIR}" ]]; then
  XMUX_INSTALL_DIR="${XMUX_INSTALL_DIR:A}"
else
  XMUX_INSTALL_DIR="$_XMUX_SOURCED_DIR"
fi
export XMUX_INSTALL_DIR

if [[ -n "${XMUX_PROJECT_DIR+x}" && -n "${XMUX_PROJECT_DIR}" ]]; then
  XMUX_PROJECT_DIR_EXPLICIT=1
  XMUX_PROJECT_DIR="${XMUX_PROJECT_DIR:A}"
else
  XMUX_PROJECT_DIR_EXPLICIT=0
fi

if [[ -n "${XMUX_STATE_DIR+x}" && -n "${XMUX_STATE_DIR}" ]]; then
  XMUX_STATE_DIR_EXPLICIT=1
  XMUX_STATE_DIR="${XMUX_STATE_DIR:A}"
else
  XMUX_STATE_DIR_EXPLICIT=0
fi

_xmux_project_root() {
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

_xmux_default_project_dir() {
  _xmux_project_root "$PWD"
}

_xmux_default_state_dir() {
  local root
  root="${XMUX_PROJECT_DIR:-$(_xmux_default_project_dir)}"
  print -r -- "$root/.codex/xmux"
}

_xmux_refresh_paths() {
  if [[ "${XMUX_PROJECT_DIR_EXPLICIT:-0}" == "0" ]]; then
    XMUX_PROJECT_DIR="$(_xmux_default_project_dir)"
    export XMUX_PROJECT_DIR
  fi
  if [[ "${XMUX_STATE_DIR_EXPLICIT:-0}" == "0" ]]; then
    XMUX_STATE_DIR="$(_xmux_default_state_dir)"
    export XMUX_STATE_DIR
  fi
  unset XMUX_DIR XMUX_HOME 2>/dev/null || true
}

_xmux_refresh_home() {
  _xmux_refresh_paths
}

_xmux_refresh_paths

XMUX_LEAD_AGENT="${XMUX_LEAD_AGENT:-codex-lead}"

_xmux_q() {
  printf '%q' "$1"
}

_xmux_path_with_install_bin() {
  local xmux_bin="$XMUX_INSTALL_DIR/bin"
  local path_value="${PATH:-/usr/bin:/bin}"
  local part result="$xmux_bin"
  for part in ${(s.:.)path_value}; do
    [[ -n "$part" && "$part" != "$xmux_bin" ]] || continue
    result+=":$part"
  done
  print -r -- "$result"
}

_xmux_runtime_env_assignments() {
  print -r -- "PATH=$(_xmux_q "$(_xmux_path_with_install_bin)") XMUX_INSTALL_DIR=$(_xmux_q "$XMUX_INSTALL_DIR") XMUX_PROJECT_DIR=$(_xmux_q "$XMUX_PROJECT_DIR") XMUX_STATE_DIR=$(_xmux_q "$XMUX_STATE_DIR")"
}

_xmux_codex_home_env_name() {
  print -r -- "CODEX_"HOME
}

_xmux_usage() {
  cat >&2 <<'EOF'
Usage:
  xmux teamCreate -t <team> [-n <session_name>] [claude|gemini|copilot ...] [--shutdown-on-lead-exit|--keep-team-on-lead-exit] [--] [codex args...]
  xmux teammateAdd -t <team> [--session <session_name>] <claude|gemini|copilot>...
  xmux teamStatus [-t <team>]
  xmux teammateStatus -t <team> [<agent>]
  xmux teammateShutdown -t <team> <agent>... [--timeout <seconds>] [--reason <reason>]
  xmux teamShutdown -t <team> [--timeout <seconds>] [--no-archive] [--reason <reason>]
  xmux [start] [-n <session_name>] [-T <team>] [--claude] [--gemini] [--copilot] [--shutdown-on-lead-exit|--keep-team-on-lead-exit] [--] [codex args...]
  xmux claude|gemini|copilot -t <team> [-n <agent_name>] [-x <timeout_sec>] [--] [provider args...]
  xmux teammates [-t <team>]
  xmux ensure -t <team> [<agent> ...] [--all] [--bridge] [--ready] [--json]
  xmux sessions [--filter <pattern>] [--all]
  xmux pane-info [<target>] [-t <team>] [-n <lines>]
  xmux doctor [-t <team>] [--log-lines <n>]
  xmux setup-codex [--skills-dir <dir>] [--without-skills]
  xmux doctor-codex
  xmux remove-codex
  xmux bridge-status [-t <team>] [<agent>] [--log-lines <n>]
  xmux recover -t <team> <agent> --restart-bridge|--restart-teammate [--session <session>]
  xmux submit-test -t <team> <agent> [--text <text>] [--delay <seconds>] [--force]
  xmux send <target> "<text>" [--clear] [--no-enter] [--force]
  xmux attach [<target>] [-t <team>]
  xmux shutdown -t <team> [--agent <agent> ...] [--timeout <seconds>] [--no-archive] [--reason <reason>]

Runs Codex as the XMux lead and exposes tmux operations through one entrypoint.
EOF
}

_xmux_member_usage() {
  local name="$1"
  cat >&2 <<EOF
Usage: ${name} -t <team> [-n <agent_name>] [-x <timeout_sec>] [--] [provider args...]
       ${name} -t <team> -s <session> [-n <agent_name>] [-x <timeout_sec>] [--] [provider args...]
EOF
}

_xmux_validate_team_name() {
  local team="$1"
  if [[ -z "$team" || "$team" == *"/"* || "$team" == "." || "$team" == ".." || "$team" == *".."* ]]; then
    echo "error: invalid XMux team name '$team'." >&2
    return 1
  fi
}

_xmux_validate_session_name() {
  local session="$1"
  if [[ -z "$session" || "$session" == *":"* || "$session" == *"."* || "$session" == *"/"* ]]; then
    echo "error: invalid XMux tmux session name '$session'." >&2
    echo "       Session names must not contain ':', '.', or '/' because tmux treats them as target syntax." >&2
    return 1
  fi
}

_xmux_team_dir() {
  print -r -- "$XMUX_STATE_DIR/teams/$1"
}

_xmux_default_session_name() {
  local dir_name="${PWD:t}"
  local safe_dir="${dir_name//[^A-Za-z0-9_-]/_}"
  [[ -z "$safe_dir" ]] && safe_dir="project"
  local dir_hash
  if command -v md5sum &>/dev/null; then
    dir_hash=$(printf '%s' "$PWD" | md5sum | head -c 6)
  elif command -v md5 &>/dev/null; then
    dir_hash=$(printf '%s' "$PWD" | md5 | head -c 6)
  else
    dir_hash=$(printf '%s' "$PWD" | cksum | awk '{print substr($1,1,6)}')
  fi
  print -r -- "xmux-${safe_dir}-${dir_hash}"
}

_xmux_team_from_session() {
  local session="$1"
  local team="${session//[^A-Za-z0-9._-]/_}"
  print -r -- "$team"
}

_xmux_ensure_team_files() {
  local team="$1"
  local team_dir inbox_dir
  team_dir="$(_xmux_team_dir "$team")"
  inbox_dir="$team_dir/inboxes"
  mkdir -p "$inbox_dir"
  mkdir -p "$team_dir/requests"
  [[ -f "$inbox_dir/$XMUX_LEAD_AGENT.json" ]] || print -r -- '[]' > "$inbox_dir/$XMUX_LEAD_AGENT.json"
  [[ -f "$team_dir/events.jsonl" ]] || : > "$team_dir/events.jsonl"
  if [[ ! -f "$team_dir/team.json" ]]; then
    python3 - "$team_dir/team.json" "$team" "$XMUX_LEAD_AGENT" <<'PY'
import json
import os
import sys

path, team, lead = sys.argv[1:4]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "schema": "xmux.team.v1",
            "name": team,
            "status": "active",
            "lead": {"name": lead, "provider": "codex", "pane": None},
            "members": {},
        },
        fh,
        indent=2,
        sort_keys=True,
        ensure_ascii=True,
    )
    fh.write("\n")
PY
  fi
}

_xmux_record_lead_pane() {
  local team="$1" pane="$2" session="$3"
  local team_dir
  team_dir="$(_xmux_team_dir "$team")"
  _xmux_ensure_team_files "$team"
  print -r -- "$pane" > "$team_dir/.lead-pane"

  python3 - "$team_dir/team.json" "$team" "$XMUX_LEAD_AGENT" "$pane" "$session" "$PWD" <<'PY'
import datetime as dt
import json
import os
import sys

path, team, lead_name, pane, session, cwd = sys.argv[1:7]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    cfg = {"schema": "xmux.team.v1", "name": team, "members": {}}
ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
cfg["name"] = cfg.get("name") or team
cfg["status"] = "active"
cfg["lead"] = {
    "name": lead_name,
    "provider": "codex",
    "pane": pane,
    "session": session,
    "cwd": cwd,
    "updated_at": ts,
}
members = cfg.setdefault("members", {})
if not isinstance(members, dict):
    members = {}
    cfg["members"] = members
existing = members.get(lead_name, {})
members[lead_name] = {
    **existing,
    "name": lead_name,
    "role": "lead",
    "provider": "codex",
    "backend": existing.get("backend", "codex"),
    "pane": pane,
    "active": True,
    "updated_at": ts,
}
tmp = f"{path}.tmp"
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
os.replace(tmp, path)
PY

  tmux set-option -p -t "$pane" @xmux-agent "$XMUX_LEAD_AGENT" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-team "$team" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-lead "1" 2>/dev/null
  tmux set-option -t "$session" @xmux-team "$team" 2>/dev/null
}

_xmux_mailbox_init_team() {
  local team="$1" pane="$2" session="$3"
  local script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  local ran=0

  if [[ -f "$script" ]]; then
    if python3 "$script" init-team "$team" \
        --lead-name "$XMUX_LEAD_AGENT" \
        --lead-provider codex \
        --lead-pane "$pane" >/dev/null 2>&1; then
      ran=1
    else
      echo "[xmux] warning: scripts/xmux_mailbox.py init-team failed; using local file scaffold." >&2
    fi
  fi

  _xmux_ensure_team_files "$team"
  _xmux_record_lead_pane "$team" "$pane" "$session"

  if (( ran == 0 )) && [[ ! -f "$script" ]]; then
    echo "[xmux] warning: scripts/xmux_mailbox.py not found; created local file scaffold only." >&2
  fi
}

_xmux_register_member() {
  local team="$1" agent="$2" provider="$3" pane="$4"
  local team_dir inbox_dir script ran
  team_dir="$(_xmux_team_dir "$team")"
  inbox_dir="$team_dir/inboxes"
  script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  ran=0

  mkdir -p "$inbox_dir"
  [[ -f "$inbox_dir/$agent.json" ]] || print -r -- '[]' > "$inbox_dir/$agent.json"
  [[ -f "$inbox_dir/$XMUX_LEAD_AGENT.json" ]] || print -r -- '[]' > "$inbox_dir/$XMUX_LEAD_AGENT.json"

  if [[ -f "$script" ]]; then
    if python3 "$script" register-member "$team" "$agent" \
        --provider "$provider" \
        --backend tmux \
        --pane "$pane" >/dev/null 2>&1; then
      ran=1
    fi
  fi

  python3 - "$team_dir/team.json" "$team" "$agent" "$provider" "$pane" <<'PY'
import datetime as dt
import json
import os
import sys

path, team, agent, provider, pane = sys.argv[1:6]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    cfg = {"schema": "xmux.team.v1", "name": team, "lead": {}, "members": {}}
members = cfg.setdefault("members", {})
if not isinstance(members, dict):
    members = {}
    cfg["members"] = members
ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
entry = {
    "name": agent,
    "role": "member",
    "provider": provider,
    "backend": "tmux",
    "pane": pane,
    "active": True,
    "updated_at": ts,
}
existing = members.get(agent, {})
members[agent] = {**existing, **entry}
cfg["name"] = cfg.get("name") or team
tmp = f"{path}.tmp"
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
os.replace(tmp, path)
PY

  print -r -- "$pane" > "$team_dir/.${agent}-pane"
  if (( ran == 0 )) && [[ -f "$script" ]]; then
    echo "[xmux] warning: mailbox member registration fell back to local config for '$agent'." >&2
  fi
}

_xmux_current_team() {
  local team=""
  if [[ -n "$TMUX" ]]; then
    team=$(tmux display-message -p '#{@xmux-team}' 2>/dev/null)
    [[ -z "$team" ]] && team=$(tmux display-message -p '#{E:@xmux-team}' 2>/dev/null)
  fi
  print -r -- "$team"
}

_xmux_find_lead_pane() {
  local team="$1" session="$2"
  local team_dir pane
  team_dir="$(_xmux_team_dir "$team")"

  if [[ -f "$team_dir/.lead-pane" ]]; then
    pane=$(< "$team_dir/.lead-pane")
    if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx -- "$pane"; then
      print -r -- "$pane"
      return 0
    fi
  fi

  if [[ -n "$session" ]] && tmux has-session -t "$session" 2>/dev/null; then
    tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null | head -1
    return 0
  fi

  if [[ -n "$TMUX_PANE" ]]; then
    print -r -- "$TMUX_PANE"
    return 0
  fi

  return 1
}

_xmux_require_tmux() {
  command -v tmux &>/dev/null || { echo "error: tmux is not installed." >&2; return 1; }
}

_xmux_pane_exists() {
  local pane="$1"
  [[ -n "$pane" ]] || return 1
  command -v tmux &>/dev/null || return 1
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx -- "$pane"
}

_xmux_pid_status() {
  local pid_file="$1"
  local pid
  if [[ ! -f "$pid_file" ]]; then
    print -r -- "none"$'\t'"-"
    return 0
  fi
  pid=$(< "$pid_file")
  if [[ -z "$pid" || "$pid" != <-> ]]; then
    print -r -- "invalid"$'\t'"${pid:-?}"
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    print -r -- "alive"$'\t'"$pid"
  else
    print -r -- "dead"$'\t'"$pid"
  fi
}

_xmux_kill_pid_file() {
  local pid_file="$1" label="$2"
  local pid
  [[ -f "$pid_file" ]] || return 0
  pid=$(< "$pid_file")
  if [[ -n "$pid" && "$pid" == <-> ]]; then
    if kill "$pid" 2>/dev/null; then
      local tries=0
      while kill -0 "$pid" 2>/dev/null && (( tries < 20 )); do
        sleep 0.05
        (( tries++ ))
      done
    fi
  else
    echo "[xmux] warning: ignoring invalid pid in $pid_file for $label." >&2
  fi
  rm -f "$pid_file"
}

_xmux_pid_command() {
  local pid="$1"
  ps -p "$pid" -o command= 2>/dev/null || ps -p "$pid" -o args= 2>/dev/null || true
}

_xmux_pid_matches_shutdown_helper() {
  local command_line="$1" kind="$2" team="$3" agent="$4"
  [[ -n "$command_line" ]] || return 1
  case "$kind" in
    bridge)
      [[ "$command_line" == *"xmux-bridge.zsh"* ]] || return 1
      [[ "$command_line" == *"$team"* && "$command_line" == *"$agent"* ]]
      ;;
    http-mcp)
      [[ "$command_line" == *"bridge-mcp-server.js"* && "$command_line" == *"--http"* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

_xmux_http_mcp_metadata_file() {
  local pid_file="$1"
  print -r -- "${pid_file:r}.json"
}

_xmux_write_http_mcp_metadata() {
  local metadata_file="$1" team="$2" agent="$3" port="$4" server_path="$5" pid="${6:-}"
  python3 - "$metadata_file" "$team" "$agent" "$port" "$server_path" "$pid" <<'PY'
import datetime as dt
import json
import os
import sys

metadata_file, team, agent, port, server_path, pid = sys.argv[1:7]
metadata = {
    "team": team,
    "agent": agent,
    "port": port,
    "server_path": server_path,
    "pid": pid,
    "updated_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
}
os.makedirs(os.path.dirname(metadata_file), exist_ok=True)
tmp = f"{metadata_file}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(metadata, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
os.replace(tmp, metadata_file)
PY
}

_xmux_http_mcp_pid_matches_metadata() {
  local pid_file="$1" pid="$2" command_line="$3" team="$4" agent="$5"
  local metadata_file
  metadata_file="$(_xmux_http_mcp_metadata_file "$pid_file")"
  [[ -f "$metadata_file" ]] || return 1
  python3 - "$metadata_file" "$pid" "$command_line" "$team" "$agent" <<'PY'
import json
import os
import sys

metadata_file, pid, command_line, team, agent = sys.argv[1:6]
try:
    with open(metadata_file, encoding="utf-8") as fh:
        metadata = json.load(fh)
except Exception:
    sys.exit(1)

if metadata.get("team") != team or metadata.get("agent") != agent:
    sys.exit(1)
if str(metadata.get("pid") or "") != str(pid):
    sys.exit(1)

server_path = str(metadata.get("server_path") or "")
server_name = os.path.basename(server_path) or "bridge-mcp-server.js"
port = str(metadata.get("port") or "")
if server_name not in command_line or "--http" not in command_line:
    sys.exit(1)
if port and port not in command_line:
    sys.exit(1)
sys.exit(0)
PY
}

_xmux_cleanup_shutdown_pid_file() {
  local pid_file="$1" label="$2" kind="$3" team="$4" agent="$5"
  local pid command_line tries=0 metadata_file
  [[ -f "$pid_file" ]] || return 0
  [[ "$kind" == "http-mcp" ]] && metadata_file="$(_xmux_http_mcp_metadata_file "$pid_file")"
  pid=$(< "$pid_file")
  if [[ -z "$pid" || "$pid" != <-> ]]; then
    echo "[xmux] warning: removing invalid pid in $pid_file for $label." >&2
    rm -f "$pid_file"
    [[ -n "${metadata_file:-}" ]] && rm -f "$metadata_file"
    return 0
  fi

  if kill -0 "$pid" 2>/dev/null; then
    command_line="$(_xmux_pid_command "$pid")"
    if [[ "$kind" == "http-mcp" ]] && ! _xmux_http_mcp_pid_matches_metadata "$pid_file" "$pid" "$command_line" "$team" "$agent"; then
      if [[ -z "$command_line" ]]; then
        echo "[xmux] warning: not killing HTTP MCP pid $pid for $label; process command could not be verified." >&2
        return 1
      fi
      if [[ "$command_line" == *"bridge-mcp-server.js"* && "$command_line" == *"--http"* ]]; then
        echo "[xmux] warning: not killing unverified HTTP MCP pid $pid for $label; removing stale pid metadata only." >&2
        rm -f "$pid_file" "${metadata_file:-}"
        return 1
      fi
      echo "[xmux] warning: removing stale pid file for $label; pid $pid does not match XMux HTTP MCP helper state." >&2
      rm -f "$pid_file" "${metadata_file:-}"
      return 0
    fi
    if ! _xmux_pid_matches_shutdown_helper "$command_line" "$kind" "$team" "$agent"; then
      if [[ -n "$command_line" ]]; then
        echo "[xmux] warning: removing stale pid file for $label; pid $pid does not match XMux helper state." >&2
        rm -f "$pid_file"
        [[ -n "${metadata_file:-}" ]] && rm -f "$metadata_file"
        return 0
      fi
      echo "[xmux] warning: not killing pid $pid for $label; process command could not be verified." >&2
      return 1
    fi
    kill "$pid" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null && (( tries < 40 )); do
      sleep 0.05
      (( tries++ ))
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "[xmux] error: failed to stop $label pid $pid." >&2
      return 1
    fi
  fi
  rm -f "$pid_file"
  [[ -n "${metadata_file:-}" ]] && rm -f "$metadata_file"
}

_xmux_remove_stale_pid_file() {
  local pid_file="$1"
  local pid_line pid_state
  [[ -f "$pid_file" ]] || return 1
  pid_line="$(_xmux_pid_status "$pid_file")"
  pid_state="${pid_line%%$'\t'*}"
  case "$pid_state" in
    dead|invalid)
      rm -f "$pid_file"
      return 0
      ;;
  esac
  return 1
}

_xmux_pid_meta_value() {
  local meta_file="$1" key="$2"
  [[ -f "$meta_file" ]] || return 1
  sed -n "s/^${key}=//p" "$meta_file" | tail -1
}

_xmux_pid_meta_matches() {
  local pid_file="$1" meta_file="$2" team="$3" agent="$4" kind="$5"
  local pid meta_pid meta_team meta_agent meta_kind
  [[ -f "$pid_file" && -f "$meta_file" ]] || return 1
  pid=$(< "$pid_file")
  meta_pid="$(_xmux_pid_meta_value "$meta_file" pid 2>/dev/null)"
  meta_team="$(_xmux_pid_meta_value "$meta_file" team 2>/dev/null)"
  meta_agent="$(_xmux_pid_meta_value "$meta_file" agent 2>/dev/null)"
  meta_kind="$(_xmux_pid_meta_value "$meta_file" kind 2>/dev/null)"
  [[ "$pid" == "$meta_pid" && "$meta_team" == "$team" && "$meta_agent" == "$agent" && "$meta_kind" == "$kind" ]]
}

_xmux_pid_process_matches() {
  local pid="$1" team="$2" agent="$3" kind="$4"
  local command_line outbox
  command_line="$(ps -p "$pid" -o command= 2>/dev/null)" || return 1
  case "$kind" in
    bridge)
      [[ "$command_line" == *"xmux-bridge.zsh"* && "$command_line" == *" -T $team"* && "$command_line" == *" -a $agent"* ]]
      ;;
    http_mcp)
      outbox="$(_xmux_team_dir "$team")/inboxes/$XMUX_LEAD_AGENT.json"
      [[ "$command_line" == *"bridge-mcp-server.js"* && "$command_line" == *"--outbox $outbox"* && "$command_line" == *"--agent $agent"* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

_xmux_pid_ownership_matches() {
  local pid_file="$1" meta_file="$2" team="$3" agent="$4" kind="$5"
  local pid command_line
  [[ -f "$pid_file" ]] || return 1
  pid=$(< "$pid_file")
	  case "$kind" in
	    bridge)
	      _xmux_pid_meta_matches "$pid_file" "$meta_file" "$team" "$agent" "$kind" \
	        && _xmux_pid_process_matches "$pid" "$team" "$agent" "$kind" \
	        && return 0
	      [[ ! -f "$meta_file" ]] && _xmux_pid_process_matches "$pid" "$team" "$agent" "$kind"
	      ;;
	    http_mcp)
	      command_line="$(_xmux_pid_command "$pid")"
	      _xmux_http_mcp_pid_matches_metadata "$pid_file" "$pid" "$command_line" "$team" "$agent"
	      ;;
	    *)
	      return 1
	      ;;
	  esac
	}

_xmux_guarded_cleanup_pid_file() {
  local pid_file="$1" meta_file="$2" team="$3" agent="$4" kind="$5" label="$6"
  local pid_line pid_state pid tries=0
  if [[ ! -f "$pid_file" ]]; then
    print -r -- "none"
    return 0
  fi

  pid_line="$(_xmux_pid_status "$pid_file")"
  pid_state="${pid_line%%$'\t'*}"
  pid="${pid_line#*$'\t'}"
  case "$pid_state" in
    none)
      rm -f "$meta_file"
      print -r -- "none"
      return 0
      ;;
    dead|invalid)
      rm -f "$pid_file" "$meta_file"
      print -r -- "removed-${pid_state}"
      return 0
      ;;
    alive)
      if ! _xmux_pid_ownership_matches "$pid_file" "$meta_file" "$team" "$agent" "$kind"; then
        rm -f "$pid_file" "$meta_file"
        print -r -- "removed-unverified"
        return 0
      fi
      if kill "$pid" 2>/dev/null; then
        while kill -0 "$pid" 2>/dev/null && (( tries < 20 )); do
          sleep 0.05
          (( tries++ ))
        done
        if kill -0 "$pid" 2>/dev/null; then
          echo "[xmux] warning: failed to stop verified $label pid $pid." >&2
          print -r -- "kill-failed"
          return 1
        fi
        rm -f "$pid_file" "$meta_file"
        print -r -- "killed"
        return 0
      fi
      echo "[xmux] warning: failed to stop verified $label pid $pid." >&2
      print -r -- "kill-failed"
      return 1
      ;;
  esac

  rm -f "$pid_file" "$meta_file"
  print -r -- "removed-${pid_state}"
}

_xmux_record_pid_meta_args() {
  local team="$1" agent="$2" kind="$3"
  print -r -- "$(_xmux_q "team=$team") $(_xmux_q "agent=$agent") $(_xmux_q "kind=$kind") \"pid=\$pid\""
}

_xmux_pid_cleanup_message() {
  local label="$1" cleanup_state="$2"
  case "$cleanup_state" in
    killed) print -r -- "stopped $label pid" ;;
    removed-dead|removed-invalid) print -r -- "removed stale $label pid" ;;
    removed-unverified) print -r -- "removed unverified $label pid without killing process" ;;
    kill-failed) print -r -- "failed to stop verified $label pid" ;;
  esac
}

_xmux_pane_state() {
  local pane="$1"
  if [[ -z "$pane" || "$pane" == "-" ]]; then
    print -r -- "no-pane"
  elif command -v tmux &>/dev/null && _xmux_pane_exists "$pane"; then
    print -r -- "alive"
  elif command -v tmux &>/dev/null && tmux list-panes -a -F '#{pane_id}' >/dev/null 2>&1; then
    print -r -- "dead"
  else
    print -r -- "unknown"
  fi
}

_xmux_pane_tags_match() {
  local pane="$1" team="$2" agent="$3"
  local line tag_team tag_agent
  [[ -n "$pane" && "$pane" != "-" ]] || return 1
  line=$(tmux display-message -t "$pane" -p $'#{@xmux-team}\t#{@xmux-agent}' 2>/dev/null) || return 1
  tag_team="${line%%$'\t'*}"
  tag_agent="${line#*$'\t'}"
  [[ "$tag_team" == "$team" && "$tag_agent" == "$agent" ]]
}

_xmux_verified_pane_state() {
  local team="$1" agent="$2" pane="$3"
  local state
  state="$(_xmux_pane_state "$pane")"
  if [[ "$state" == "alive" ]] && ! _xmux_pane_tags_match "$pane" "$team" "$agent"; then
    print -r -- "stale"
  else
    print -r -- "$state"
  fi
}

_xmux_start_provider_member() {
  local provider="$1" team="$2" agent="$3" session="$4"
  case "$provider" in
    claude) xmux-claude -t "$team" -n "$agent" -s "$session" ;;
    gemini) xmux-gemini -t "$team" -n "$agent" -s "$session" ;;
    copilot) xmux-copilot -t "$team" -n "$agent" -s "$session" ;;
    *) echo "error: unsupported provider '$provider'." >&2; return 1 ;;
  esac
}

_xmux_ensure_file_from_template() {
  local target="$1" source="$2"
  if [[ ! -f "$source" ]]; then
    print -r -- "missing-source"
    return 1
  fi
  python3 - "$target" "$source" <<'PY'
import os
import sys
import tempfile

target, source = sys.argv[1:3]
begin = "<!-- XMUX_PROTOCOL_BEGIN -->"
end = "<!-- XMUX_PROTOCOL_END -->"

try:
    with open(source, encoding="utf-8") as fh:
        template = fh.read().strip()
except OSError:
    print("missing-source")
    raise SystemExit(1)

block = f"{begin}\n{template}\n{end}\n"
try:
    with open(target, encoding="utf-8") as fh:
        original = fh.read()
except FileNotFoundError:
    original = None
except OSError:
    print("read-failed")
    raise SystemExit(1)

if original is None:
    new_text = block
    action = "created"
else:
    start = original.find(begin)
    stop = original.find(end, start + len(begin)) if start >= 0 else -1
    if start >= 0 and stop >= 0:
        stop += len(end)
        current = original[start:stop]
        desired = block.rstrip("\n")
        if current.strip() == desired.strip():
            print("exists")
            raise SystemExit(0)
        new_text = original[:start] + desired + original[stop:]
        if not new_text.endswith("\n"):
            new_text += "\n"
        action = "refreshed"
    else:
        prefix = original.rstrip()
        new_text = f"{prefix}\n\n{block}" if prefix else block
        action = "updated"

parent = os.path.dirname(target)
tmp = None
try:
    if parent:
        os.makedirs(parent, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        dir=parent or ".",
        delete=False,
        suffix=".tmp",
        encoding="utf-8",
    ) as fh:
        fh.write(new_text)
        tmp = fh.name
    os.replace(tmp, target)
except OSError:
    try:
        os.unlink(tmp)
    except Exception:
        pass
    print("write-failed")
    raise SystemExit(1)

print(action)
PY
}

_xmux_protocol_file_has_block() {
  local target="$1" source="$2"
  [[ -f "$target" && -f "$source" ]] || return 1
  python3 - "$target" "$source" <<'PY'
import sys

target, source = sys.argv[1:3]
begin = "<!-- XMUX_PROTOCOL_BEGIN -->"
end = "<!-- XMUX_PROTOCOL_END -->"

try:
    with open(target, encoding="utf-8") as fh:
        text = fh.read()
    with open(source, encoding="utf-8") as fh:
        template = fh.read().strip()
except OSError:
    sys.exit(1)

start = text.find(begin)
stop = text.find(end, start + len(begin)) if start >= 0 else -1
if start < 0 or stop < 0:
    sys.exit(1)
body = text[start + len(begin):stop].strip()
if body != template:
    sys.exit(1)
required = ("write_to_lead", "request_id")
if not all(item in body for item in required):
    sys.exit(1)
sys.exit(0)
PY
}

_xmux_copilot_config_url() {
  python3 - <<'PY'
import json
import os

path = os.path.expanduser("~/.copilot/mcp-config.json")
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    raise SystemExit

server = (cfg.get("mcpServers") or {}).get("xmux_bridge") or {}
if server.get("type") == "sse" and server.get("url"):
    print(server["url"])
PY
}

_xmux_gemini_config_has_bridge() {
  local expected="$1"
  python3 - "$expected" <<'PY'
import json
import os
import sys

expected = sys.argv[1]
path = os.path.expanduser("~/.gemini/settings.json")
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)
server = (cfg.get("mcpServers") or {}).get("xmux_bridge")
if (
    isinstance(server, dict)
    and server.get("command") == "node"
    and (server.get("args") or [None])[0] == expected
):
    sys.exit(0)
sys.exit(1)
PY
}

_xmux_target_json() {
  local agent="$1" provider="$2" pane_id="$3" pane_state="$4"
  local bridge_state="$5" bridge_pid="$6" http_state="$7" http_pid="$8"
  local mailbox_state="$9" ready="${10}" actions_text="${11}" issues_text="${12}"
  python3 - "$agent" "$provider" "$pane_id" "$pane_state" "$bridge_state" "$bridge_pid" \
    "$http_state" "$http_pid" "$mailbox_state" "$ready" "$actions_text" "$issues_text" <<'PY'
import json
import sys

(
    agent,
    provider,
    pane_id,
    pane_state,
    bridge_state,
    bridge_pid,
    http_state,
    http_pid,
    mailbox_state,
    ready,
    actions_text,
    issues_text,
) = sys.argv[1:13]

def clean_pid(value):
    if value and value.isdigit():
        return int(value)
    return None

def clean_id(value):
    return None if value in {"", "-"} else value

sep = "\x1f"
record = {
    "agent": agent,
    "provider": provider,
    "pane": {"id": clean_id(pane_id), "state": pane_state},
    "bridge": {"state": bridge_state, "pid": clean_pid(bridge_pid)},
    "http_mcp": {"state": http_state, "pid": clean_pid(http_pid)},
    "mailbox": {"state": mailbox_state},
    "ready": ready == "true",
    "actions": [item for item in actions_text.split(sep) if item],
    "issues": [item for item in issues_text.split(sep) if item],
}
print(json.dumps(record, separators=(",", ":"), ensure_ascii=True))
PY
}

_xmux_ensure_json() {
  local team="$1" ready="$2"
  shift 2
  python3 - "$team" "$ready" "$@" <<'PY'
import json
import sys

team, ready = sys.argv[1:3]
targets = [json.loads(item) for item in sys.argv[3:]]
payload = {"team": team, "ready": ready == "true", "targets": targets}
print(json.dumps(payload, indent=2, ensure_ascii=True))
PY
}

_xmux_ensure_human() {
  local team="$1" ready="$2"
  shift 2
  python3 - "$team" "$ready" "$@" <<'PY'
import json
import sys

team, ready = sys.argv[1:3]
targets = [json.loads(item) for item in sys.argv[3:]]
print(f"XMux ensure team={team} ready={ready}")
if not targets:
    print("(no targets)")
    raise SystemExit
print(f"{'AGENT':20} {'PROVIDER':10} {'PANE':10} {'BRIDGE':12} {'HTTP-MCP':12} {'READY':5} ISSUES")
for item in targets:
    pane = item["pane"]
    bridge = item["bridge"]
    http = item["http_mcp"]
    pane_text = f"{pane.get('state')}:{pane.get('id') or '-'}"
    bridge_text = f"{bridge.get('state')}:{bridge.get('pid') or '-'}"
    http_text = f"{http.get('state')}:{http.get('pid') or '-'}"
    issues = ", ".join(item.get("issues") or [])
    print(
        f"{item.get('agent','-'):20} {item.get('provider','-'):10} "
        f"{pane_text:10} {bridge_text:12} {http_text:12} "
        f"{str(item.get('ready')).lower():5} {issues}"
    )
PY
}

_xmux_select_pane_if_alive() {
  local pane="$1"
  [[ -n "$pane" ]] || return 1
  _xmux_pane_exists "$pane" || return 1
  tmux select-pane -t "$pane" 2>/dev/null
}

_xmux_tmux_wait_expected_sigterm() {
  print -r -- 'wait "$!"; rc=$?; case "$rc" in 0|143) exit 0 ;; *) exit "$rc" ;; esac'
}

_xmux_provider_idle_pattern() {
  local provider="$1"
  case "$provider" in
    gemini) print -r -- "Type your message" ;;
    copilot) print -r -- "/ commands" ;;
    *) print -r -- "" ;;
  esac
}

_xmux_provider_submit_delay() {
  local provider="$1"
  if [[ "$provider" == "copilot" && -z "${XMUX_SUBMIT_DELAY:-}" ]]; then
    print -r -- "0.8"
  else
    print -r -- "${XMUX_SUBMIT_DELAY:-0.2}"
  fi
}

_xmux_bridge_env_value() {
  local env_file="$1" key="$2"
  [[ -f "$env_file" ]] || return 1
  sed -n "s/^${key}=//p" "$env_file" | tail -1
}

_xmux_known_teams() {
  python3 - "$XMUX_STATE_DIR" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
teams_dir = root / "teams"
if not teams_dir.is_dir():
    raise SystemExit

inactive = {"archived", "shutdown", "inactive", "deleted"}
for cfg_path in sorted(teams_dir.glob("*/team.json")):
    try:
        with open(cfg_path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except Exception:
        continue
    status = str(cfg.get("status") or "active")
    if status not in inactive:
        print(cfg_path.parent.name)
PY
}

_xmux_team_is_active() {
  local team="$1"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" <<'PY'
import json
import sys

inactive = {"archived", "shutdown", "inactive", "deleted"}
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)
status = str(cfg.get("status") or "active")
sys.exit(1 if status in inactive else 0)
PY
}

_xmux_member_field() {
  local team="$1" agent="$2" field="$3"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  python3 - "$cfg" "$agent" "$field" <<'PY'
import json
import sys

path, agent, field = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)

members = cfg.get("members") or {}
entry = members.get(agent)
lead = cfg.get("lead") or {}
if entry is None and lead.get("name") == agent:
    entry = lead
if not isinstance(entry, dict):
    sys.exit(1)

value = entry.get(field)
if value is None and field == "session" and lead.get("name") == agent:
    value = lead.get("session")
if value is None:
    value = ""
print(str(value))
PY
}

_xmux_emit_member_records() {
  local team="$1" active_only="${2:-0}"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  python3 - "$cfg" "$team" "$active_only" <<'PY'
import json
import sys

path, team, active_only = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)

lead = cfg.get("lead") or {}
members = dict(cfg.get("members") or {})
lead_name = lead.get("name")
if lead_name and lead_name not in members:
    members[lead_name] = {
        "name": lead_name,
        "role": "lead",
        "provider": lead.get("provider", "codex"),
        "pane": lead.get("pane"),
        "session": lead.get("session"),
        "active": True,
    }

def clean(value):
    if value is None or value == "":
        return "-"
    return str(value).replace("\t", " ").replace("\n", " ") or "-"

rows = []
for name, entry in members.items():
    if not isinstance(entry, dict):
        continue
    role = entry.get("role") or ("lead" if name == lead_name else "member")
    if role == "lead":
        continue
    active = entry.get("active", True)
    if active_only == "1" and active is False:
        continue
    rows.append((
        clean(name),
        [
            clean(team),
            clean(name),
            clean(role),
            clean(entry.get("provider")),
            "true" if active is not False else "false",
            clean(entry.get("pane")),
            clean(entry.get("session")),
            clean(entry.get("display_mode") or entry.get("mode") or "split"),
            clean(entry.get("updated_at")),
        ],
    ))

for _, values in sorted(rows):
    print("\t".join(values))
PY
}

_xmux_member_record_for_target() {
  local team="$1" target="$2"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  python3 - "$cfg" "$team" "$target" <<'PY'
import json
import sys

path, team, target = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)

lead = cfg.get("lead") or {}
members = dict(cfg.get("members") or {})
lead_name = lead.get("name")
if lead_name and lead_name not in members:
    members[lead_name] = {
        "name": lead_name,
        "role": "lead",
        "provider": lead.get("provider", "codex"),
        "pane": lead.get("pane"),
        "session": lead.get("session"),
        "active": True,
    }

def clean(value):
    if value is None or value == "":
        return "-"
    return str(value).replace("\t", " ").replace("\n", " ") or "-"

rows = []
for name, entry in members.items():
    if not isinstance(entry, dict):
        continue
    pane = entry.get("pane")
    if name != target and pane != target:
        continue
    role = entry.get("role") or ("lead" if name == lead_name else "member")
    active = entry.get("active", True)
    session = entry.get("session")
    if role == "lead":
        session = session or lead.get("session")
    rows.append((
        0 if role == "lead" else 1,
        clean(name),
        [
            clean(team),
            clean(name),
            clean(role),
            clean(entry.get("provider")),
            "true" if active is not False else "false",
            clean(pane),
            clean(session),
            clean(entry.get("display_mode") or entry.get("mode") or "split"),
            clean(entry.get("updated_at")),
        ],
    ))

for _, _, values in sorted(rows):
    print("\t".join(values))
PY
}

_xmux_resolve_member_ref() {
  local target="$1" team_hint="${2:-}"
  local target_team target_agent team line
  local -a records teams

  [[ -n "$target" ]] || { echo "error: target is required." >&2; return 2; }

  if [[ "$target" == *:* ]]; then
    target_team="${target%%:*}"
    target_agent="${target#*:}"
    if [[ -n "$team_hint" && "$team_hint" != "$target_team" ]]; then
      echo "error: target team '$target_team' conflicts with -t '$team_hint'." >&2
      return 2
    fi
    _xmux_validate_team_name "$target_team" || return 2
    records=("${(@f)$(_xmux_member_record_for_target "$target_team" "$target_agent" 2>/dev/null)}")
  elif [[ -n "$team_hint" ]]; then
    _xmux_validate_team_name "$team_hint" || return 2
    records=("${(@f)$(_xmux_member_record_for_target "$team_hint" "$target" 2>/dev/null)}")
  else
    teams=("${(@f)$(_xmux_known_teams)}")
    for team in "${teams[@]}"; do
      [[ -z "$team" ]] && continue
      records+=("${(@f)$(_xmux_member_record_for_target "$team" "$target" 2>/dev/null)}")
    done
  fi

  local -a nonempty=()
  for line in "${records[@]}"; do
    [[ -n "$line" ]] && nonempty+=("$line")
  done
  records=("${nonempty[@]}")

  if (( ${#records[@]} == 0 )); then
    if [[ -n "$team_hint" ]]; then
      echo "error: XMux member '$target' not found in team '$team_hint'." >&2
    else
      echo "error: XMux member '$target' not found." >&2
    fi
    return 2
  fi
  if (( ${#records[@]} > 1 )); then
    echo "error: target '$target' matches multiple XMux members:" >&2
    local row row_team row_name
    for row in "${records[@]}"; do
      row_team="${row%%$'\t'*}"
      row="${row#*$'\t'}"
      row_name="${row%%$'\t'*}"
      echo "  - $row_team:$row_name" >&2
    done
    echo "use exact form: xmux <command> -t <team> <agent>" >&2
    return 2
  fi

  print -r -- "${records[1]}"
}

_xmux_emit_team_members() {
  local team="$1"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  python3 - "$cfg" "$team" <<'PY'
import json
import sys

path, team = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)

lead = cfg.get("lead") or {}
members = dict(cfg.get("members") or {})
lead_name = lead.get("name")
if lead_name and lead_name not in members:
    members[lead_name] = {
        "name": lead_name,
        "role": "lead",
        "provider": lead.get("provider", "codex"),
        "pane": lead.get("pane"),
        "session": lead.get("session"),
        "active": True,
    }

def clean(value):
    if value is None or value == "":
        return "-"
    text = str(value).replace("\t", " ").replace("\n", " ")
    return text or "-"

rows = []
for name, entry in members.items():
    if not isinstance(entry, dict):
        continue
    role = entry.get("role") or ("lead" if name == lead_name else "member")
    if role == "lead":
        entry.setdefault("session", lead.get("session"))
    rows.append((
        0 if role == "lead" else 1,
        name,
        [
            clean(team),
            clean(name),
            clean(role),
            clean(entry.get("provider")),
            "true" if entry.get("active", True) else "false",
            clean(entry.get("pane")),
            clean(entry.get("session")),
            clean(entry.get("display_mode") or entry.get("mode") or "split"),
            clean(entry.get("updated_at")),
        ],
    ))

for _, _, values in sorted(rows):
    print("\t".join(values))
PY
}

_xmux_session_for_team() {
  local team="$1"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  local session s

  if [[ -f "$cfg" ]]; then
    session=$(python3 - "$cfg" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(0)
print((cfg.get("lead") or {}).get("session") or "")
PY
)
    if [[ -n "$session" && "$session" != *:* && "$session" != *.* && "$session" != */* ]] \
        && command -v tmux &>/dev/null && tmux has-session -t "$session" 2>/dev/null; then
      print -r -- "$session"
      return 0
    fi
  fi

  command -v tmux &>/dev/null || return 1
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    [[ "$s" == *:* || "$s" == *.* || "$s" == */* ]] && continue
    if [[ "$(tmux show-option -v -t "$s" @xmux-team 2>/dev/null)" == "$team" ]]; then
      print -r -- "$s"
      return 0
    fi
  done < <(tmux list-sessions -F '#S' 2>/dev/null)
  return 1
}

_xmux_resolve_target_to_pane() {
  local target="$1" team_hint="${2:-}"
  local team agent pane session
  local -a matches=()

  _xmux_require_tmux || return 1

  if [[ -z "$target" ]]; then
    if [[ -n "$TMUX_PANE" ]] && _xmux_pane_exists "$TMUX_PANE"; then
      print -r -- "$TMUX_PANE"
      return 0
    fi
    echo "error: target is required outside tmux." >&2
    return 1
  fi

  if [[ "$target" =~ '^%[0-9]+$' ]]; then
    if _xmux_pane_exists "$target"; then
      print -r -- "$target"
      return 0
    fi
    echo "error: pane '$target' not found." >&2
    return 1
  fi

  if [[ "$target" == *:* ]]; then
    team="${target%%:*}"
    agent="${target#*:}"
    _xmux_validate_team_name "$team" || return 1
    pane="$(_xmux_member_field "$team" "$agent" pane 2>/dev/null)"
    if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
      print -r -- "$pane"
      return 0
    fi
    echo "error: XMux target '$target' has no live pane." >&2
    return 1
  fi

  if [[ -n "$team_hint" ]]; then
    _xmux_validate_team_name "$team_hint" || return 1
    pane="$(_xmux_member_field "$team_hint" "$target" pane 2>/dev/null)"
    if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
      print -r -- "$pane"
      return 0
    fi
  fi

  if [[ "$target" != *:* && "$target" != *.* ]] && tmux has-session -t "$target" 2>/dev/null; then
    pane=$(tmux list-panes -t "$target" -F '#{?pane_active,#{pane_id},}' 2>/dev/null | grep -v '^$' | head -1)
    if [[ -n "$pane" ]]; then
      print -r -- "$pane"
      return 0
    fi
  fi

  for team in $(_xmux_known_teams); do
    pane="$(_xmux_member_field "$team" "$target" pane 2>/dev/null)"
    if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
      matches+=("$team:$target=$pane")
    fi
  done

  if (( ${#matches[@]} == 1 )); then
    print -r -- "${matches[1]##*=}"
    return 0
  fi
  if (( ${#matches[@]} > 1 )); then
    echo "error: target '$target' matches multiple XMux members:" >&2
    local match
    for match in "${matches[@]}"; do
      echo "  - ${match%%=*} (pane ${match##*=})" >&2
    done
    echo "use exact form: xmux <command> team:agent ..." >&2
    return 2
  fi

  echo "error: target '$target' not found." >&2
  echo "  tried: pane id, tmux session, team:agent, XMux agent name" >&2
  return 1
}

_xmux_cmd_sessions() {
  local pattern="" all=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --filter)
        [[ $# -ge 2 ]] || { echo "error: --filter requires a pattern." >&2; return 1; }
        pattern="$2"
        shift 2
        ;;
      --all)
        all=1
        shift
        ;;
      -h|--help)
        echo "Usage: xmux sessions [--filter <pattern>] [--all]"
        return 0
        ;;
      *)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
    esac
  done

  _xmux_require_tmux || return 1

  local -a raw=()
  local line name attached windows team pane cmd shown=0
  raw=("${(@f)$(tmux list-sessions -F $'#{session_name}\t#{session_attached}\t#{session_windows}' 2>/dev/null)}")
  if (( ${#raw[@]} == 0 )) || [[ -z "${raw[1]}" ]]; then
    echo "no tmux sessions."
    return 0
  fi

  printf "%-28s %-18s %-8s %-8s %-8s %s\n" "SESSION" "TEAM" "PANES" "ATTACHED" "ACTIVE" "COMMAND"
  for line in "${raw[@]}"; do
    [[ -z "$line" ]] && continue
    name="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    attached="${line%%$'\t'*}"
    windows="${line#*$'\t'}"
    if [[ "$name" == *:* || "$name" == *.* ]]; then
      team=""
    else
      team=$(tmux show-option -v -t "$name" @xmux-team 2>/dev/null || true)
    fi
    if [[ -n "$team" ]] && ! _xmux_team_is_active "$team"; then
      team=""
    fi
    if [[ -z "$team" && "$all" -eq 0 ]]; then
      continue
    fi
    if [[ -n "$pattern" && "$name" != $~pattern && "$team" != $~pattern ]]; then
      continue
    fi
    if [[ "$name" == *:* || "$name" == *.* ]]; then
      pane=""
      cmd=""
    else
      pane=$(tmux list-panes -t "$name" -F '#{?pane_active,#{pane_id},}' 2>/dev/null | grep -v '^$' | head -1)
      cmd=$(tmux display-message -t "${pane:-$name}" -p '#{pane_current_command}' 2>/dev/null || true)
    fi
    printf "%-28s %-18s %-8s %-8s %-8s %s\n" "$name" "${team:--}" "$windows" "$attached" "${pane:--}" "${cmd:--}"
    shown=$(( shown + 1 ))
  done

  if (( shown == 0 )); then
    if [[ "$all" -eq 1 ]]; then
      echo "(no sessions match)"
    else
      echo "(no XMux sessions match; use --all to include non-XMux tmux sessions)"
    fi
  fi
}

_xmux_cmd_teammates() {
  local team="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux teammates [-t <team>]"
        return 0
        ;;
      *)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
    esac
  done

  local -a teams=()
  if [[ -n "$team" ]]; then
    _xmux_validate_team_name "$team" || return 1
    teams=("$team")
  else
    team="$(_xmux_current_team)"
    if [[ -n "$team" ]]; then
      teams=("$team")
    else
      teams=("${(@f)$(_xmux_known_teams)}")
    fi
  fi

  if (( ${#teams[@]} == 0 )); then
    echo "no XMux teams found."
    return 0
  fi

  local have_tmux=0
  command -v tmux &>/dev/null && tmux list-panes -a -F '#{pane_id}' >/dev/null 2>&1 && have_tmux=1

  local line row_team name role provider active pane session mode updated member_status bridge pid_file pid
  printf "%-18s %-7s %-20s %-10s %-8s %-10s %-8s %s\n" "TEAM" "ROLE" "AGENT" "PROVIDER" "PANE" "MODE" "STATUS" "BRIDGE"
  for team in "${teams[@]}"; do
    if [[ ! -f "$(_xmux_team_dir "$team")/team.json" ]]; then
      echo "warning: team '$team' not found." >&2
      continue
    fi
    while IFS=$'\t' read -r row_team name role provider active pane session mode updated; do
      [[ -z "$name" ]] && continue
      if [[ "$active" != "true" ]]; then
        member_status="inactive"
      elif [[ "$pane" == "-" ]]; then
        member_status="no-pane"
      elif (( have_tmux )) && _xmux_pane_exists "$pane"; then
        member_status="alive"
      elif (( have_tmux )); then
        member_status="dead"
      else
        member_status="unknown"
      fi

      bridge="-"
      if [[ "$role" != "lead" ]]; then
        pid_file="$(_xmux_team_dir "$row_team")/.${name}-bridge.pid"
        if [[ -f "$pid_file" ]]; then
          pid=$(< "$pid_file")
          if kill -0 "$pid" 2>/dev/null; then
            bridge="alive"
          else
            bridge="dead"
          fi
        else
          bridge="none"
        fi
      fi

      printf "%-18s %-7s %-20s %-10s %-8s %-10s %-8s %s\n" \
        "$row_team" "$role" "$name" "$provider" "$pane" "$mode" "$member_status" "$bridge"
    done < <(_xmux_emit_team_members "$team")
  done
}

_xmux_cmd_pane_info() {
  local target="" team="" lines=30 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -n)
        [[ $# -ge 2 ]] || { echo "error: -n requires a line count." >&2; return 1; }
        lines="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux pane-info [<target>] [-t <team>] [-n <lines>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        [[ -z "$target" ]] || { echo "error: extra argument '$arg'" >&2; return 1; }
        target="$arg"
        shift
        ;;
    esac
  done

  local pane
  pane="$(_xmux_resolve_target_to_pane "$target" "$team")" || return $?

  local session window pane_index cmd pid cwd agent team_name is_lead
  session=$(tmux display-message -t "$pane" -p '#{session_name}' 2>/dev/null)
  window=$(tmux display-message -t "$pane" -p '#{window_index}' 2>/dev/null)
  pane_index=$(tmux display-message -t "$pane" -p '#{pane_index}' 2>/dev/null)
  cmd=$(tmux display-message -t "$pane" -p '#{pane_current_command}' 2>/dev/null)
  pid=$(tmux display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null)
  cwd=$(tmux display-message -t "$pane" -p '#{pane_current_path}' 2>/dev/null)
  agent=$(tmux display-message -t "$pane" -p '#{@xmux-agent}' 2>/dev/null)
  team_name=$(tmux display-message -t "$pane" -p '#{@xmux-team}' 2>/dev/null)
  is_lead=$(tmux display-message -t "$pane" -p '#{@xmux-lead}' 2>/dev/null)

  printf "pane:        %s\n" "$pane"
  printf "session:     %s\n" "$session"
  printf "window.pane: %s.%s\n" "$window" "$pane_index"
  printf "process:     %s (pid %s)\n" "$cmd" "$pid"
  printf "cwd:         %s\n" "$cwd"
  [[ -n "$team_name" ]] && printf "team:        %s\n" "$team_name"
  [[ -n "$agent" ]] && printf "agent:       %s%s\n" "$agent" "$([[ "$is_lead" == "1" ]] && printf ' (lead)')"

  if [[ "$lines" != "0" ]]; then
    local neg_lines=$(( -lines ))
    printf "last %s lines:\n" "$lines"
    tmux capture-pane -t "$pane" -p -S "$neg_lines" 2>/dev/null | sed 's/^/  /'
  fi
}

_xmux_mailbox_status_summary() {
  local team="$1" script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  local payload
  if [[ ! -f "$script" ]]; then
    echo "mailbox: unavailable (scripts/xmux_mailbox.py not found)"
    return 0
  fi
  payload=$(python3 "$script" team-status "$team" 2>/dev/null) || {
    echo "mailbox: error reading team-status"
    return 0
  }
  python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
team_status = payload.get("team_status") or payload.get("status", "unknown")
print(f"mailbox: status={team_status} team_dir={payload.get('team_dir', '-')}")
inboxes = payload.get("inboxes") or {}
if inboxes:
    parts = []
    for name in sorted(inboxes):
        entry = inboxes[name] or {}
        parts.append(f"{name}:{entry.get('unread', 0)}/{entry.get('total', 0)}")
    print("inboxes: " + ", ".join(parts))
else:
    print("inboxes: none")
requests = payload.get("requests") or {}
print(
    "requests: "
    f"total={requests.get('total', 0)} "
    f"pending={requests.get('pending', 0)} "
    f"done={requests.get('done', 0)}"
)
PY
}

_xmux_pending_requests_summary() {
  local team="$1" script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  local payload
  if [[ ! -f "$script" ]]; then
    return 0
  fi
  payload=$(python3 "$script" list-requests "$team" --status pending 2>/dev/null) || return 0
  python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
requests = payload.get("requests") or []
if not requests:
    print("pending requests: none")
    raise SystemExit

print("pending requests:")
for req in requests[:10]:
    print(
        "  - "
        f"id={req.get('request_id', '-')} "
        f"from={req.get('from', '-')} "
        f"to={req.get('to', '-')} "
        f"status={req.get('status', '-')} "
        f"updated={req.get('updated_at') or req.get('created_at') or '-'}"
    )
if len(requests) > 10:
    print(f"  ... {len(requests) - 10} more pending requests")
PY
}

_xmux_cmd_bridge_status() {
  local team="" target="" log_lines=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      --log-lines)
        [[ $# -ge 2 ]] || { echo "error: --log-lines requires a number." >&2; return 1; }
        log_lines="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux bridge-status [-t <team>] [<agent>] [--log-lines <n>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        [[ -z "$target" ]] || { echo "error: extra argument '$arg'" >&2; return 1; }
        target="$arg"
        shift
        ;;
    esac
  done

  if [[ "$target" == *:* ]]; then
    local target_team="${target%%:*}"
    local target_agent="${target#*:}"
    if [[ -n "$team" && "$team" != "$target_team" ]]; then
      echo "error: target team '$target_team' conflicts with -t '$team'." >&2
      return 1
    fi
    team="$target_team"
    target="$target_agent"
  fi

  local -a teams=()
  if [[ -n "$team" ]]; then
    _xmux_validate_team_name "$team" || return 1
    teams=("$team")
  else
    team="$(_xmux_current_team)"
    if [[ -n "$team" ]]; then
      teams=("$team")
    else
      teams=("${(@f)$(_xmux_known_teams)}")
    fi
  fi

  if (( ${#teams[@]} == 0 )) || [[ -z "${teams[1]:-}" ]]; then
    echo "no XMux teams found."
    return 0
  fi

  local have_tmux=0
  command -v tmux &>/dev/null && tmux list-panes -a -F '#{pane_id}' >/dev/null 2>&1 && have_tmux=1

  local row_team name role provider active pane session mode updated
  local team_dir pid_file http_pid_file pid_line bridge_status bridge_pid http_status http_pid
  local pane_status env_file idle_pattern submit_delay log_file found=0
  local -a log_files=()

  printf "%-18s %-20s %-10s %-8s %-10s %-12s %-12s %-18s %-6s %s\n" \
    "TEAM" "AGENT" "PROVIDER" "PANE" "PANE-STAT" "BRIDGE" "HTTP-MCP" "IDLE" "DELAY" "LOG"
  for team in "${teams[@]}"; do
    if [[ ! -f "$(_xmux_team_dir "$team")/team.json" ]]; then
      echo "warning: team '$team' not found." >&2
      continue
    fi
    while IFS=$'\t' read -r row_team name role provider active pane session mode updated; do
      [[ -z "$name" || "$role" == "lead" ]] && continue
      [[ -n "$target" && "$name" != "$target" ]] && continue
      found=$(( found + 1 ))
      team_dir="$(_xmux_team_dir "$row_team")"

      if [[ "$pane" == "-" ]]; then
        pane_status="no-pane"
      elif (( have_tmux )) && _xmux_pane_exists "$pane"; then
        pane_status="alive"
      elif (( have_tmux )); then
        pane_status="dead"
      else
        pane_status="unknown"
      fi

      pid_file="$team_dir/.${name}-bridge.pid"
      pid_line="$(_xmux_pid_status "$pid_file")"
      bridge_status="${pid_line%%$'\t'*}"
      bridge_pid="${pid_line#*$'\t'}"

      http_pid_file="$team_dir/.${name}-mcp-http.pid"
      pid_line="$(_xmux_pid_status "$http_pid_file")"
      http_status="${pid_line%%$'\t'*}"
      http_pid="${pid_line#*$'\t'}"

      env_file="$team_dir/.bridge-${name}.env"
      idle_pattern="$(_xmux_bridge_env_value "$env_file" XMUX_IDLE_PATTERN 2>/dev/null)"
      [[ -z "$idle_pattern" ]] && idle_pattern="$(_xmux_provider_idle_pattern "$provider")"
      [[ -z "$idle_pattern" ]] && idle_pattern="-"
      submit_delay="$(_xmux_bridge_env_value "$env_file" XMUX_SUBMIT_DELAY 2>/dev/null)"
      [[ -z "$submit_delay" ]] && submit_delay="$(_xmux_provider_submit_delay "$provider")"
      log_file="$(_xmux_bridge_env_value "$env_file" XMUX_BRIDGE_LOG 2>/dev/null)"
      [[ -z "$log_file" ]] && log_file="/tmp/xmux-bridge-${row_team}-${name}.log"

      printf "%-18s %-20s %-10s %-8s %-10s %-12s %-12s %-18s %-6s %s\n" \
        "$row_team" "$name" "$provider" "$pane" "$pane_status" \
        "${bridge_status}:${bridge_pid}" "${http_status}:${http_pid}" \
        "$idle_pattern" "$submit_delay" "$log_file"
      if (( log_lines > 0 )) && [[ -f "$log_file" ]]; then
        log_files+=("$row_team"$'\t'"$name"$'\t'"$log_file")
      fi
    done < <(_xmux_emit_team_members "$team")
  done

  if (( found == 0 )); then
    echo "no matching XMux teammate bridges."
  fi

  if (( log_lines > 0 && ${#log_files[@]} > 0 )); then
    local entry log_team log_agent log_path
    for entry in "${log_files[@]}"; do
      log_team="${entry%%$'\t'*}"
      entry="${entry#*$'\t'}"
      log_agent="${entry%%$'\t'*}"
      log_path="${entry#*$'\t'}"
      echo
      echo "log tail: $log_team:$log_agent ($log_path)"
      tail -n "$log_lines" "$log_path" 2>/dev/null | sed 's/^/  /'
    done
  fi
}

_xmux_cmd_doctor() {
  local team="" log_lines=12 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      --log-lines)
        [[ $# -ge 2 ]] || { echo "error: --log-lines requires a number." >&2; return 1; }
        log_lines="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux doctor [-t <team>] [--log-lines <n>]"
        return 0
        ;;
      *)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
    esac
  done

  local -a teams=()
  if [[ -n "$team" ]]; then
    _xmux_validate_team_name "$team" || return 1
    teams=("$team")
  else
    team="$(_xmux_current_team)"
    if [[ -n "$team" ]]; then
      teams=("$team")
    else
      teams=("${(@f)$(_xmux_known_teams)}")
    fi
  fi

  echo "XMux doctor"
  echo
  echo "Sessions:"
  if command -v tmux &>/dev/null; then
    _xmux_cmd_sessions
  else
    echo "tmux: unavailable"
  fi

  if (( ${#teams[@]} == 0 )) || [[ -z "${teams[1]:-}" ]]; then
    echo
    echo "no XMux teams found."
    return 0
  fi

  local scoped_team
  for scoped_team in "${teams[@]}"; do
    echo
    echo "Team: $scoped_team"
    _xmux_mailbox_status_summary "$scoped_team"
    _xmux_pending_requests_summary "$scoped_team"
    echo
    echo "Teammates:"
    _xmux_cmd_teammates -t "$scoped_team"
    echo
    echo "Bridge status:"
    _xmux_cmd_bridge_status -t "$scoped_team" --log-lines "$log_lines"
  done
}

_xmux_cmd_send() {
  local target="" prompt="" file="" team="" clear=0 no_enter=0 force=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --to)
        [[ $# -ge 2 ]] || { echo "error: --to requires a target." >&2; return 1; }
        target="$2"
        shift 2
        ;;
      --prompt)
        [[ $# -ge 2 ]] || { echo "error: --prompt requires text." >&2; return 1; }
        prompt="$2"
        shift 2
        ;;
      --file)
        [[ $# -ge 2 ]] || { echo "error: --file requires a path." >&2; return 1; }
        file="$2"
        shift 2
        ;;
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      --clear)
        clear=1
        shift
        ;;
      --no-enter)
        no_enter=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      --)
        shift
        prompt="$*"
        break
        ;;
      -h|--help)
        echo "Usage: xmux send <target> \"<text>\" [--clear] [--no-enter] [--force]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        if [[ -z "$target" ]]; then
          target="$arg"
        elif [[ -z "$prompt" ]]; then
          prompt="$arg"
        else
          echo "error: text must be quoted as a single argument." >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  [[ -n "$target" ]] || { echo "error: target is required." >&2; return 1; }
  if [[ -n "$prompt" && -n "$file" ]]; then
    echo "error: --prompt and --file are mutually exclusive." >&2
    return 1
  fi
  if [[ -z "$prompt" && -z "$file" ]]; then
    echo "error: provide text or --file." >&2
    return 1
  fi
  if [[ -n "$file" && ! -r "$file" ]]; then
    echo "error: file not readable: $file" >&2
    return 1
  fi
  if [[ -n "$prompt" && "$force" -eq 0 ]]; then
    local first_char
    first_char=$(printf '%s' "$prompt" | sed 's/^[[:space:]]*//' | cut -c1)
    if [[ "$first_char" == "/" ]]; then
      echo "warning: prompt starts with '/'; use --force if this is intentional." >&2
      return 1
    fi
  fi

  local pane buf
  pane="$(_xmux_resolve_target_to_pane "$target" "$team")" || return $?
  buf="xmux-send-$$-$RANDOM"

  if [[ -n "$file" ]]; then
    tmux load-buffer -b "$buf" "$file" || return 1
  else
    printf '%s' "$prompt" | tmux load-buffer -b "$buf" - || return 1
  fi
  if (( clear )); then
    tmux send-keys -t "$pane" C-u 2>/dev/null || { tmux delete-buffer -b "$buf" 2>/dev/null; return 1; }
  fi
  tmux paste-buffer -p -b "$buf" -t "$pane" || { tmux delete-buffer -b "$buf" 2>/dev/null; return 1; }
  tmux delete-buffer -b "$buf" 2>/dev/null
  if (( ! no_enter )); then
    tmux send-keys -t "$pane" Enter
  fi
}

_xmux_cmd_attach() {
  local target="" team="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux attach [<target>] [-t <team>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        [[ -z "$target" ]] || { echo "error: extra argument '$arg'" >&2; return 1; }
        target="$arg"
        shift
        ;;
    esac
  done

  _xmux_require_tmux || return 1

  local session="" pane=""
  if [[ -n "$team" && -z "$target" ]]; then
    _xmux_validate_team_name "$team" || return 1
    session="$(_xmux_session_for_team "$team")" || { echo "error: no live tmux session for team '$team'." >&2; return 1; }
  elif [[ -n "$target" && "$target" != *:* && "$target" != *.* ]] && tmux has-session -t "$target" 2>/dev/null; then
    session="$target"
  else
    pane="$(_xmux_resolve_target_to_pane "$target" "$team")" || return $?
    session=$(tmux display-message -t "$pane" -p '#{session_name}' 2>/dev/null)
  fi

  [[ -n "$session" ]] || { echo "error: cannot resolve tmux session." >&2; return 1; }
  _xmux_validate_session_name "$session" || return 1
  [[ -n "$pane" ]] && tmux select-pane -t "$pane" 2>/dev/null
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$session"
  else
    tmux attach-session -t "$session"
  fi
}

_xmux_mark_member_inactive() {
  local team="$1" agent="$2"
  local script="$XMUX_INSTALL_DIR/scripts/xmux_mailbox.py"
  if [[ -f "$script" ]]; then
    python3 "$script" update-member "$team" "$agent" --active false >/dev/null 2>&1 && return 0
  fi

  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" "$agent" <<'PY'
import datetime as dt
import json
import os
import sys

path, agent = sys.argv[1:3]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
members = cfg.setdefault("members", {})
if agent in members and isinstance(members[agent], dict):
    ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    members[agent]["active"] = False
    members[agent]["updated_at"] = ts
    cfg["updated_at"] = ts
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2, sort_keys=True, ensure_ascii=True)
        fh.write("\n")
    os.replace(tmp, path)
PY
}

_xmux_mark_team_shutdown_start() {
  local team="$1" reason="$2" team_dir cfg events
  team_dir="$(_xmux_team_dir "$team")"
  cfg="$team_dir/team.json"
  events="$team_dir/events.jsonl"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" "$events" "$team" "$reason" <<'PY'
import datetime as dt
import json
import os
import sys

cfg_path, events_path, team, reason = sys.argv[1:5]
ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
with open(cfg_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
shutdown = dict(cfg.get("shutdown") or {})
shutdown.update({"reason": reason, "started_at": shutdown.get("started_at", ts), "status": "shutting_down"})
cfg["shutdown"] = shutdown
cfg["status"] = "shutting_down"
cfg["updated_at"] = ts
tmp = f"{cfg_path}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
os.replace(tmp, cfg_path)
record = {
    "ts": ts,
    "event": "team.shutdown_started",
    "actor": "xmux",
    "target": team,
    "request_id": None,
    "data": {"reason": reason},
}
with open(events_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, sort_keys=True, ensure_ascii=True) + "\n")
PY
}

_xmux_mark_team_shutdown_complete() {
  local team="$1" reason="$2" shutdown_status="$3" archive_path="${4:-}"
  local team_dir cfg events metadata
  team_dir="$(_xmux_team_dir "$team")"
  cfg="$team_dir/team.json"
  events="$team_dir/events.jsonl"
  metadata="$team_dir/shutdown.json"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" "$events" "$metadata" "$team" "$reason" "$shutdown_status" "$archive_path" <<'PY'
import datetime as dt
import json
import os
import sys

cfg_path, events_path, metadata_path, team, reason, status, archive_path = sys.argv[1:8]
ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
with open(cfg_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
members = cfg.setdefault("members", {})
lead_name = (cfg.get("lead") or {}).get("name")
for name, entry in members.items():
    if not isinstance(entry, dict) or name == lead_name or entry.get("role") == "lead":
        continue
    entry["active"] = False
    entry["updated_at"] = ts
shutdown = dict(cfg.get("shutdown") or {})
shutdown.pop("failed_agents", None)
shutdown.pop("failed_at", None)
shutdown.update({"reason": reason, "completed_at": ts, "status": status})
if archive_path:
    shutdown["archive_path"] = archive_path
cfg["shutdown"] = shutdown
cfg["status"] = status
cfg["updated_at"] = ts
tmp = f"{cfg_path}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
os.replace(tmp, cfg_path)
metadata = {
    "team": team,
    "reason": reason,
    "status": status,
    "shutdown_completed_at": ts,
}
if archive_path:
    metadata["archive_path"] = archive_path
with open(metadata_path, "w", encoding="utf-8") as fh:
    json.dump(metadata, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
record = {
    "ts": ts,
    "event": "team.shutdown_completed",
    "actor": "xmux",
    "target": team,
    "request_id": None,
    "data": {"reason": reason, "status": status, "archive_path": archive_path or None},
}
with open(events_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, sort_keys=True, ensure_ascii=True) + "\n")
PY
}

_xmux_mark_team_shutdown_degraded() {
  local team="$1" reason="$2" failures="$3"
  local team_dir cfg events
  team_dir="$(_xmux_team_dir "$team")"
  cfg="$team_dir/team.json"
  events="$team_dir/events.jsonl"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" "$events" "$team" "$reason" "$failures" <<'PY'
import datetime as dt
import json
import os
import sys

cfg_path, events_path, team, reason, failures = sys.argv[1:6]
failed_agents = [item for item in failures.split(",") if item]
ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
with open(cfg_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
shutdown = dict(cfg.get("shutdown") or {})
shutdown.update({
    "reason": reason,
    "failed_agents": failed_agents,
    "failed_at": ts,
    "status": "degraded",
})
cfg["shutdown"] = shutdown
cfg["status"] = "degraded"
cfg["updated_at"] = ts
tmp = f"{cfg_path}.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
os.replace(tmp, cfg_path)
record = {
    "ts": ts,
    "event": "team.shutdown_degraded",
    "actor": "xmux",
    "target": team,
    "request_id": None,
    "data": {"reason": reason, "failed_agents": failed_agents},
}
with open(events_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, sort_keys=True, ensure_ascii=True) + "\n")
PY
}

_xmux_pane_matches_member() {
  local team="$1" agent="$2" pane="$3"
  local tags pane_team pane_agent
  tags=$(tmux display-message -t "$pane" -p '#{@xmux-team}'$'\t''#{@xmux-agent}' 2>/dev/null) || return 1
  pane_team="${tags%%$'\t'*}"
  pane_agent="${tags#*$'\t'}"
  [[ "$pane_team" == "$team" && "$pane_agent" == "$agent" ]]
}

_xmux_clear_team_tmux_metadata() {
  local team="$1"
  command -v tmux &>/dev/null || return 0

  local session pane tags pane_team is_lead
  session="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" session 2>/dev/null)"
  [[ -z "$session" ]] && session="$(_xmux_session_for_team "$team" 2>/dev/null)"
  if [[ -n "$session" && "$session" != *:* && "$session" != *.* && "$session" != */* ]] \
      && tmux has-session -t "$session" 2>/dev/null \
      && [[ "$(tmux show-option -v -t "$session" @xmux-team 2>/dev/null)" == "$team" ]]; then
    tmux set-option -u -t "$session" @xmux-team 2>/dev/null || true
  fi

  pane="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" pane 2>/dev/null)"
  if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
    tags=$(tmux display-message -t "$pane" -p '#{@xmux-team}'$'\t''#{@xmux-lead}' 2>/dev/null || true)
    pane_team="${tags%%$'\t'*}"
    is_lead="${tags#*$'\t'}"
    if [[ "$pane_team" == "$team" && "$is_lead" == "1" ]]; then
      tmux set-option -p -u -t "$pane" @xmux-agent 2>/dev/null || true
      tmux set-option -p -u -t "$pane" @xmux-team 2>/dev/null || true
      tmux set-option -p -u -t "$pane" @xmux-lead 2>/dev/null || true
    fi
  fi
}

_xmux_shutdown_teammate() {
  local team="$1" agent="$2" provider="$3" pane="$4" timeout="$5"
  local team_dir tries max_tries rc=0
  local bridge_pid_file bridge_meta_file bridge_cleanup bridge_cleanup_rc
  local http_pid_file http_meta_file http_cleanup http_cleanup_rc
  team_dir="$(_xmux_team_dir "$team")"

  bridge_pid_file="$team_dir/.${agent}-bridge.pid"
  bridge_meta_file="$team_dir/.${agent}-bridge.meta"
  http_pid_file="$team_dir/.${agent}-mcp-http.pid"
  http_meta_file="$(_xmux_http_mcp_metadata_file "$http_pid_file")"

  bridge_cleanup="$(_xmux_guarded_cleanup_pid_file "$bridge_pid_file" "$bridge_meta_file" "$team" "$agent" "bridge" "$team:$agent bridge" 2>/dev/null)"
  bridge_cleanup_rc=$?
  http_cleanup="$(_xmux_guarded_cleanup_pid_file "$http_pid_file" "$http_meta_file" "$team" "$agent" "http_mcp" "$team:$agent http mcp" 2>/dev/null)"
  http_cleanup_rc=$?
  if (( http_cleanup_rc == 0 )); then
    rm -f "$team_dir/.${agent}-mcp-http.url"
  fi

  if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
    if _xmux_pane_matches_member "$team" "$agent" "$pane"; then
      tmux send-keys -t "$pane" C-c 2>/dev/null || true
      tmux send-keys -t "$pane" C-c 2>/dev/null || true
      tries=0
      max_tries=$(( timeout * 10 ))
      while _xmux_pane_exists "$pane" && (( tries < max_tries )); do
        sleep 0.1
        (( tries++ ))
      done
      if _xmux_pane_exists "$pane"; then
        tmux kill-pane -t "$pane" 2>/dev/null || true
      fi
      tries=0
      while _xmux_pane_exists "$pane" && (( tries < 10 )); do
        sleep 0.1
        (( tries++ ))
      done
      if _xmux_pane_exists "$pane"; then
        echo "[xmux] error: failed to stop $team:$agent pane:$pane." >&2
        rc=1
      fi
    else
      echo "[xmux] warning: ignoring stale pane id $pane for $team:$agent; tmux pane tags do not match." >&2
    fi
  fi

  if (( bridge_cleanup_rc != 0 )); then
    tries=0
    max_tries=$(( timeout * 10 ))
    (( max_tries < 20 )) && max_tries=20
    while (( tries < max_tries )); do
      bridge_cleanup="$(_xmux_guarded_cleanup_pid_file "$bridge_pid_file" "$bridge_meta_file" "$team" "$agent" "bridge" "$team:$agent bridge" 2>/dev/null)"
      bridge_cleanup_rc=$?
      (( bridge_cleanup_rc == 0 )) && break
      sleep 0.1
      (( tries++ ))
    done
  fi
  if (( http_cleanup_rc != 0 )); then
    tries=0
    max_tries=$(( timeout * 10 ))
    (( max_tries < 20 )) && max_tries=20
    while (( tries < max_tries )); do
      http_cleanup="$(_xmux_guarded_cleanup_pid_file "$http_pid_file" "$http_meta_file" "$team" "$agent" "http_mcp" "$team:$agent http mcp" 2>/dev/null)"
      http_cleanup_rc=$?
      if (( http_cleanup_rc == 0 )); then
        rm -f "$team_dir/.${agent}-mcp-http.url"
        break
      fi
      sleep 0.1
      (( tries++ ))
    done
  fi
  if (( bridge_cleanup_rc == 0 )) && [[ ! -f "$bridge_pid_file" ]]; then
    rm -f "$bridge_meta_file"
  fi
  if (( http_cleanup_rc == 0 )) && [[ ! -f "$http_pid_file" ]]; then
    rm -f "$http_meta_file" "$team_dir/.${agent}-mcp-http.url"
  fi

  if (( bridge_cleanup_rc != 0 || http_cleanup_rc != 0 )); then
    echo "[xmux] error: failed to stop verified helper for $team:$agent cleanup:bridge=${bridge_cleanup:-none} http=${http_cleanup:-none}" >&2
    rc=1
  fi

  if (( rc == 0 )); then
    _xmux_mark_member_inactive "$team" "$agent" || true
  fi
  return "$rc"
}

_xmux_write_archive_metadata() {
  local archive_dir="$1" team="$2" reason="$3"
  python3 - "$archive_dir" "$team" "$reason" <<'PY'
import datetime as dt
import json
import os
import sys

archive_dir, team, reason = sys.argv[1:4]
ts = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
metadata = {
    "team": team,
    "archived_at": ts,
    "reason": reason,
    "status": "archived",
}
with open(os.path.join(archive_dir, "archive.json"), "w", encoding="utf-8") as fh:
    json.dump(metadata, fh, indent=2, sort_keys=True, ensure_ascii=True)
    fh.write("\n")
events_path = os.path.join(archive_dir, "events.jsonl")
record = {
    "ts": ts,
    "event": "team.archived",
    "actor": "xmux",
    "target": team,
    "request_id": None,
    "data": {"reason": reason, "archive_dir": archive_dir},
}
with open(events_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, sort_keys=True, ensure_ascii=True) + "\n")
PY
}

_xmux_archive_team_dir() {
  local team="$1" reason="$2" team_dir archive_root stamp base archive_dir suffix
  team_dir="$(_xmux_team_dir "$team")"
  archive_root="$XMUX_STATE_DIR/archive"
  mkdir -p "$archive_root"
  stamp=$(python3 - <<'PY'
import datetime as dt
print(dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
PY
)
  base="$archive_root/${stamp}-${team}"
  archive_dir="$base"
  suffix=2
  while [[ -e "$archive_dir" ]]; do
    archive_dir="${base}-${suffix}"
    suffix=$(( suffix + 1 ))
  done
  _xmux_mark_team_shutdown_complete "$team" "$reason" "archived" "$archive_dir" || return 1
  mv "$team_dir" "$archive_dir" || return 1
  _xmux_write_archive_metadata "$archive_dir" "$team" "$reason"
  print -r -- "$archive_dir"
}

_xmux_free_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

_xmux_start_copilot_mcp() {
  local team="$1" agent="$2" outbox="$3"
  local team_dir pid_file metadata_file url_file port url log_file

  team_dir="$(_xmux_team_dir "$team")"
  pid_file="$team_dir/.${agent}-mcp-http.pid"
  metadata_file="$(_xmux_http_mcp_metadata_file "$pid_file")"
  url_file="$team_dir/.${agent}-mcp-http.url"
  log_file="/tmp/xmux-mcp-http-${team}-${agent}.log"

  mkdir -p "$team_dir/inboxes"
  [[ -f "$outbox" ]] || print -r -- '[]' > "$outbox"

  _xmux_guarded_cleanup_pid_file "$pid_file" "$metadata_file" "$team" "$agent" "http_mcp" "$team:$agent http mcp" >/dev/null 2>&1 || return 1

  port="$(_xmux_free_port)" || return 1
  url="http://127.0.0.1:${port}/sse"
  local env_prefix mcp_cmd wait_cmd
  env_prefix="$(_xmux_runtime_env_assignments)"
  wait_cmd="$(_xmux_tmux_wait_expected_sigterm)"
  mcp_cmd="env -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_OUTBOX=$(_xmux_q "$outbox") XMUX_AGENT=$(_xmux_q "$agent") XMUX_TEAM=$(_xmux_q "$team") node $(_xmux_q "$XMUX_INSTALL_DIR/bridge-mcp-server.js") --http $(_xmux_q "$port") --outbox $(_xmux_q "$outbox") --agent $(_xmux_q "$agent") >> $(_xmux_q "$log_file") 2>&1 & pid=\"\$!\"; printf '%s\n' \"\$pid\" > $(_xmux_q "$pid_file"); $wait_cmd"
  tmux run-shell -b "$mcp_cmd" || return 1
  print -r -- "$url" > "$url_file"

  local tries=0
  until curl -sf "$url" -o /dev/null --max-time 0.2 2>/dev/null \
      || (( tries++ >= 10 )); do
    sleep 0.2
  done

  local started_pid=""
  [[ -f "$pid_file" ]] && started_pid=$(< "$pid_file")
  _xmux_write_http_mcp_metadata "$metadata_file" "$team" "$agent" "$port" "$XMUX_INSTALL_DIR/bridge-mcp-server.js" "$started_pid" || true

  if [[ -f "$XMUX_INSTALL_DIR/scripts/setup_copilot_mcp.py" ]]; then
    python3 "$XMUX_INSTALL_DIR/scripts/setup_copilot_mcp.py" "$url" >/dev/null
  fi
}

_xmux_prepare_gemini_mcp() {
  local script="$XMUX_INSTALL_DIR/scripts/setup_gemini_mcp.py"
  [[ -f "$script" ]] || { echo "error: cannot find $script." >&2; return 1; }
  python3 "$script" "$XMUX_INSTALL_DIR/bridge-mcp-server.js" >/dev/null || return 1
}

_xmux_gemini_args_have_model() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --model|--model=*|-m|-m=*)
        return 0
        ;;
    esac
  done
  return 1
}

_xmux_resolve_gemini_model_env() {
  local model="$1"
  [[ -n "$model" ]] || return 1
  case "$model" in
    default)
      print -r -- "auto"
      ;;
    *)
      print -r -- "$model"
      ;;
  esac
}

_xmux_provider_env_assignments() {
  local provider="$1" model
  shift
  if [[ "$provider" == "gemini" ]] && ! _xmux_gemini_args_have_model "$@"; then
    model="$(_xmux_resolve_gemini_model_env "${XMUX_GEMINI_MODEL:-}")" || return 0
    print -r -- "GEMINI_MODEL=$(_xmux_q "$model")"
  fi
}

_xmux_start_member_bridge() {
  local team="$1" agent="$2" provider="$3" pane="$4" timeout="$5" idle_pattern="$6" submit_delay="$7"
  local team_dir inbox outbox bridge_log

  team_dir="$(_xmux_team_dir "$team")"
  inbox="$team_dir/inboxes/$agent.json"
  outbox="$team_dir/inboxes/$XMUX_LEAD_AGENT.json"
  bridge_log="/tmp/xmux-bridge-${team}-${agent}.log"

  mkdir -p "$team_dir/inboxes"
  [[ -f "$inbox" ]] || print -r -- '[]' > "$inbox"
  [[ -f "$outbox" ]] || print -r -- '[]' > "$outbox"

  [[ -f "$XMUX_INSTALL_DIR/xmux-bridge.zsh" ]] || { echo "error: cannot find $XMUX_INSTALL_DIR/xmux-bridge.zsh." >&2; return 1; }
  printf 'XMUX_INSTALL_DIR=%s\nXMUX_PROJECT_DIR=%s\nXMUX_STATE_DIR=%s\nXMUX_OUTBOX=%s\nXMUX_AGENT=%s\nXMUX_TEAM=%s\nXMUX_PROVIDER=%s\nXMUX_IDLE_PATTERN=%s\nXMUX_SUBMIT_DELAY=%s\nXMUX_BRIDGE_LOG=%s\n' \
    "$XMUX_INSTALL_DIR" "$XMUX_PROJECT_DIR" "$XMUX_STATE_DIR" "$outbox" "$agent" "$team" "$provider" "$idle_pattern" "$submit_delay" "$bridge_log" > "$team_dir/.bridge-${agent}.env"

  local bridge_cmd env_prefix pid_file meta_file wait_cmd meta_args
  pid_file="$team_dir/.${agent}-bridge.pid"
  meta_file="$team_dir/.${agent}-bridge.meta"
  env_prefix="$(_xmux_runtime_env_assignments)"
  wait_cmd="$(_xmux_tmux_wait_expected_sigterm)"
  meta_args="$(_xmux_record_pid_meta_args "$team" "$agent" "bridge")"
  bridge_cmd="env -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_LEAD_AGENT=$(_xmux_q "$XMUX_LEAD_AGENT") zsh $(_xmux_q "$XMUX_INSTALL_DIR/xmux-bridge.zsh") -p $(_xmux_q "$pane") -T $(_xmux_q "$team") -a $(_xmux_q "$agent") -P $(_xmux_q "$provider") -i $(_xmux_q "$inbox") -x $(_xmux_q "$timeout") -w $(_xmux_q "$idle_pattern") -d $(_xmux_q "$submit_delay") >> $(_xmux_q "$bridge_log") 2>&1 & pid=\"\$!\"; printf '%s\n' \"\$pid\" > $(_xmux_q "$pid_file"); printf '%s\n' $meta_args > $(_xmux_q "$meta_file"); $wait_cmd"
  tmux run-shell -b "$bridge_cmd" || return 1
}

_xmux_ensure_one_record() {
  local record="$1" want_bridge="$2" want_ready="$3"
  local team agent role provider active pane session mode updated
  IFS=$'\t' read -r team agent role provider active pane session mode updated <<< "$record"

  local team_dir bridge_pid_file bridge_meta_file http_pid_file http_meta_file http_url_file env_file inbox outbox
  local pane_state bridge_line bridge_state bridge_pid http_line http_state http_pid
  local timeout idle_pattern submit_delay mailbox_state target_ready expected_url config_url
  local sep actions_text issues_text file_state copilot_prompt gemini_prompt cleanup_status cleanup_message cleanup_rc cleanup_failed
  local -a actions issues

  team_dir="$(_xmux_team_dir "$team")"
  bridge_pid_file="$team_dir/.${agent}-bridge.pid"
  bridge_meta_file="$team_dir/.${agent}-bridge.meta"
  http_pid_file="$team_dir/.${agent}-mcp-http.pid"
  http_meta_file="$(_xmux_http_mcp_metadata_file "$http_pid_file")"
  http_url_file="$team_dir/.${agent}-mcp-http.url"
  env_file="$team_dir/.bridge-${agent}.env"
  inbox="$team_dir/inboxes/$agent.json"
  outbox="$team_dir/inboxes/$XMUX_LEAD_AGENT.json"
  copilot_prompt="$XMUX_PROJECT_DIR/.github/copilot-instructions.md"
  gemini_prompt="$XMUX_PROJECT_DIR/.gemini/GEMINI.md"
  timeout=60
  mailbox_state="ok"

  if [[ ! -d "$team_dir/inboxes" ]]; then
    mkdir -p "$team_dir/inboxes" && actions+=("created mailbox inbox directory") || issues+=("mailbox inbox directory could not be created")
  fi
  if [[ ! -f "$inbox" ]]; then
    print -r -- '[]' > "$inbox" && actions+=("created mailbox inbox") || issues+=("mailbox inbox could not be created")
  fi
  if [[ ! -f "$outbox" ]]; then
    print -r -- '[]' > "$outbox" && actions+=("created lead outbox") || issues+=("lead outbox could not be created")
  fi
  if [[ ! -f "$inbox" || ! -f "$outbox" ]]; then
    mailbox_state="error"
  fi

  pane_state="$(_xmux_verified_pane_state "$team" "$agent" "$pane")"
  [[ "$pane_state" == "stale" ]] && issues+=("pane tag mismatch")
  if (( want_ready )) && [[ "$pane_state" != "alive" ]]; then
    if ! command -v tmux &>/dev/null; then
      issues+=("tmux unavailable; cannot restart teammate")
    else
      [[ -z "$session" || "$session" == "-" ]] && session="$(_xmux_session_for_team "$team" 2>/dev/null)"
      if [[ -z "$session" || "$session" == "-" ]]; then
        issues+=("tmux session not found; cannot restart teammate")
      else
        cleanup_failed=0
        cleanup_status="$(_xmux_guarded_cleanup_pid_file "$bridge_pid_file" "$bridge_meta_file" "$team" "$agent" "bridge" "$team:$agent bridge" 2>/dev/null)"
        cleanup_rc=$?
        cleanup_message="$(_xmux_pid_cleanup_message "bridge" "$cleanup_status")"
        [[ -n "$cleanup_message" ]] && actions+=("$cleanup_message")
        if (( cleanup_rc != 0 )); then
          issues+=("bridge cleanup failed")
          cleanup_failed=1
        fi
        cleanup_status="$(_xmux_guarded_cleanup_pid_file "$http_pid_file" "$http_meta_file" "$team" "$agent" "http_mcp" "$team:$agent http mcp" 2>/dev/null)"
        cleanup_rc=$?
        cleanup_message="$(_xmux_pid_cleanup_message "Copilot HTTP MCP" "$cleanup_status")"
        [[ -n "$cleanup_message" ]] && actions+=("$cleanup_message")
        if (( cleanup_rc != 0 )); then
          issues+=("Copilot HTTP MCP cleanup failed")
          cleanup_failed=1
        fi
        if (( cleanup_failed == 0 )); then
          rm -f "$http_url_file"
          _xmux_mark_member_inactive "$team" "$agent" >/dev/null 2>&1 || true
          if _xmux_start_provider_member "$provider" "$team" "$agent" "$session" >/dev/null; then
            actions+=("restarted teammate")
            pane="$(_xmux_member_field "$team" "$agent" pane 2>/dev/null)"
            pane_state="$(_xmux_verified_pane_state "$team" "$agent" "$pane")"
            [[ "$pane_state" == "stale" ]] && issues+=("restarted pane tag mismatch")
          else
            issues+=("teammate restart failed")
          fi
        else
          issues+=("teammate restart blocked by cleanup failure")
        fi
      fi
    fi
  fi

  if (( want_ready )); then
    case "$provider" in
      copilot)
        file_state="$(_xmux_ensure_file_from_template "$copilot_prompt" "$XMUX_INSTALL_DIR/prompt/COPILOT.md" 2>/dev/null)"
        case "$file_state" in
          created) actions+=("created .github/copilot-instructions.md") ;;
          updated) actions+=("installed XMux Copilot protocol block") ;;
          refreshed) actions+=("refreshed XMux Copilot protocol block") ;;
          exists) ;;
          *) issues+=("Copilot XMux protocol block missing") ;;
        esac
        _xmux_protocol_file_has_block "$copilot_prompt" "$XMUX_INSTALL_DIR/prompt/COPILOT.md" \
          || issues+=("Copilot XMux protocol block not installed")
        ;;
      gemini)
        file_state="$(_xmux_ensure_file_from_template "$gemini_prompt" "$XMUX_INSTALL_DIR/prompt/GEMINI.md" 2>/dev/null)"
        case "$file_state" in
          created) actions+=("created .gemini/GEMINI.md") ;;
          updated) actions+=("installed XMux Gemini protocol block") ;;
          refreshed) actions+=("refreshed XMux Gemini protocol block") ;;
          exists) ;;
          *) issues+=("Gemini XMux protocol block missing") ;;
        esac
        _xmux_protocol_file_has_block "$gemini_prompt" "$XMUX_INSTALL_DIR/prompt/GEMINI.md" \
          || issues+=("Gemini XMux protocol block not installed")
        if ! _xmux_gemini_config_has_bridge "$XMUX_INSTALL_DIR/bridge-mcp-server.js"; then
          if _xmux_prepare_gemini_mcp >/dev/null; then
            actions+=("configured Gemini MCP bridge")
          else
            issues+=("Gemini MCP bridge config failed")
          fi
        fi
        ;;
    esac
  fi

  if (( want_bridge || want_ready )); then
    bridge_line="$(_xmux_pid_status "$bridge_pid_file")"
    bridge_state="${bridge_line%%$'\t'*}"
    if [[ "$bridge_state" == "dead" || "$bridge_state" == "invalid" ]] \
        || { [[ "$bridge_state" == "alive" ]] && ! _xmux_pid_ownership_matches "$bridge_pid_file" "$bridge_meta_file" "$team" "$agent" "bridge"; }; then
      cleanup_status="$(_xmux_guarded_cleanup_pid_file "$bridge_pid_file" "$bridge_meta_file" "$team" "$agent" "bridge" "$team:$agent bridge" 2>/dev/null)"
      cleanup_rc=$?
      cleanup_message="$(_xmux_pid_cleanup_message "bridge" "$cleanup_status")"
      [[ -n "$cleanup_message" ]] && actions+=("$cleanup_message")
      if (( cleanup_rc == 0 )); then
        bridge_state="none"
      else
        issues+=("bridge cleanup failed")
      fi
    fi
    pane_state="$(_xmux_verified_pane_state "$team" "$agent" "$pane")"
    [[ "$pane_state" == "stale" ]] && issues+=("pane tag mismatch")
    if [[ "$bridge_state" != "alive" ]]; then
      if [[ "$pane_state" == "alive" ]]; then
        idle_pattern="$(_xmux_bridge_env_value "$env_file" XMUX_IDLE_PATTERN 2>/dev/null)"
        [[ -z "$idle_pattern" ]] && idle_pattern="$(_xmux_provider_idle_pattern "$provider")"
        submit_delay="$(_xmux_bridge_env_value "$env_file" XMUX_SUBMIT_DELAY 2>/dev/null)"
        [[ -z "$submit_delay" ]] && submit_delay="$(_xmux_provider_submit_delay "$provider")"
        if _xmux_start_member_bridge "$team" "$agent" "$provider" "$pane" "$timeout" "$idle_pattern" "$submit_delay" >/dev/null; then
          actions+=("started bridge")
        else
          issues+=("bridge start failed")
        fi
      else
        issues+=("bridge requires live pane")
      fi
    fi
  fi

  if (( want_ready )) && [[ "$provider" == "copilot" ]]; then
    http_line="$(_xmux_pid_status "$http_pid_file")"
    http_state="${http_line%%$'\t'*}"
    if [[ "$http_state" == "dead" || "$http_state" == "invalid" ]] \
        || { [[ "$http_state" == "alive" ]] && ! _xmux_pid_ownership_matches "$http_pid_file" "$http_meta_file" "$team" "$agent" "http_mcp"; }; then
      cleanup_status="$(_xmux_guarded_cleanup_pid_file "$http_pid_file" "$http_meta_file" "$team" "$agent" "http_mcp" "$team:$agent http mcp" 2>/dev/null)"
      cleanup_rc=$?
      cleanup_message="$(_xmux_pid_cleanup_message "Copilot HTTP MCP" "$cleanup_status")"
      [[ -n "$cleanup_message" ]] && actions+=("$cleanup_message")
      if (( cleanup_rc == 0 )); then
        rm -f "$http_url_file"
        http_state="none"
      else
        issues+=("Copilot HTTP MCP cleanup failed")
      fi
    fi
    if [[ "$http_state" != "alive" ]]; then
      if command -v tmux &>/dev/null; then
        if _xmux_start_copilot_mcp "$team" "$agent" "$outbox" >/dev/null; then
          actions+=("started Copilot HTTP MCP")
        else
          issues+=("Copilot HTTP MCP start failed")
        fi
      else
        issues+=("tmux unavailable; cannot start Copilot HTTP MCP")
      fi
    fi
    if [[ -f "$http_url_file" ]]; then
      expected_url="$(< "$http_url_file")"
      config_url="$(_xmux_copilot_config_url 2>/dev/null)"
      if [[ -n "$expected_url" && "$config_url" != "$expected_url" ]]; then
        if [[ -f "$XMUX_INSTALL_DIR/scripts/setup_copilot_mcp.py" ]] \
            && python3 "$XMUX_INSTALL_DIR/scripts/setup_copilot_mcp.py" "$expected_url" >/dev/null; then
          actions+=("updated Copilot MCP config")
        else
          issues+=("Copilot MCP config update failed")
        fi
      fi
    elif [[ -z "$(_xmux_copilot_config_url 2>/dev/null)" ]]; then
      issues+=("Copilot MCP SSE URL not discoverable")
    fi
  fi

  pane_state="$(_xmux_verified_pane_state "$team" "$agent" "$pane")"
  [[ "$pane_state" == "stale" ]] && issues+=("pane tag mismatch")
  bridge_line="$(_xmux_pid_status "$bridge_pid_file")"
  bridge_state="${bridge_line%%$'\t'*}"
  bridge_pid="${bridge_line#*$'\t'}"
  if [[ "$provider" == "copilot" ]]; then
    http_line="$(_xmux_pid_status "$http_pid_file")"
    http_state="${http_line%%$'\t'*}"
    http_pid="${http_line#*$'\t'}"
  else
    http_state="not_applicable"
    http_pid="-"
  fi

  target_ready=1
  if (( want_bridge || want_ready )); then
    [[ "$pane_state" == "alive" ]] || target_ready=0
    [[ "$bridge_state" == "alive" ]] || target_ready=0
  fi
  if (( want_ready )); then
    case "$provider" in
      copilot)
        [[ "$http_state" == "alive" ]] || target_ready=0
        _xmux_protocol_file_has_block "$copilot_prompt" "$XMUX_INSTALL_DIR/prompt/COPILOT.md" || target_ready=0
        if [[ -f "$http_url_file" ]]; then
          expected_url="$(< "$http_url_file")"
          [[ "$(_xmux_copilot_config_url 2>/dev/null)" == "$expected_url" ]] || target_ready=0
        else
          [[ -n "$(_xmux_copilot_config_url 2>/dev/null)" ]] || target_ready=0
        fi
        ;;
      gemini)
        _xmux_protocol_file_has_block "$gemini_prompt" "$XMUX_INSTALL_DIR/prompt/GEMINI.md" || target_ready=0
        _xmux_gemini_config_has_bridge "$XMUX_INSTALL_DIR/bridge-mcp-server.js" || target_ready=0
        ;;
    esac
  fi
  [[ "$mailbox_state" == "ok" ]] || target_ready=0

  if (( target_ready == 0 )); then
    (( want_bridge || want_ready )) && [[ "$pane_state" != "alive" ]] && issues+=("pane $pane_state")
    (( want_bridge || want_ready )) && [[ "$bridge_state" != "alive" ]] && issues+=("bridge $bridge_state")
    if (( want_ready )) && [[ "$provider" == "copilot" && "$http_state" != "alive" ]]; then
      issues+=("Copilot HTTP MCP $http_state")
    fi
  fi

  sep=$'\037'
  if (( ${#actions[@]} )); then
    actions_text="$(printf '%s\037' "${actions[@]}")"
    actions_text="${actions_text%$sep}"
  else
    actions_text=""
  fi
  if (( ${#issues[@]} )); then
    issues_text="$(printf '%s\037' "${issues[@]}")"
    issues_text="${issues_text%$sep}"
  else
    issues_text=""
  fi

  _xmux_target_json "$agent" "$provider" "$pane" "$pane_state" "$bridge_state" "$bridge_pid" \
    "$http_state" "$http_pid" "$mailbox_state" "$([[ "$target_ready" == "1" ]] && print true || print false)" \
    "$actions_text" "$issues_text"
  return $(( target_ready == 1 ? 0 : 1 ))
}

_xmux_cmd_ensure() {
  local team="" all=0 want_bridge=0 want_ready=0 json_output=0 arg
  local -a requested records target_jsons

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 2; }
        team="$2"
        shift 2
        ;;
      --all)
        all=1
        shift
        ;;
      --bridge)
        want_bridge=1
        shift
        ;;
      --ready)
        want_ready=1
        shift
        ;;
      --json)
        json_output=1
        shift
        ;;
      -h|--help)
        echo "Usage: xmux ensure -t <team> [<agent> ...] [--all] [--bridge] [--ready] [--json]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 2
        ;;
      *)
        requested+=("$arg")
        shift
        ;;
    esac
  done

  [[ -n "$team" ]] || { echo "error: -t <team> is required for ensure scope." >&2; return 2; }
  _xmux_validate_team_name "$team" || return 2
  [[ -f "$(_xmux_team_dir "$team")/team.json" ]] || { echo "error: XMux team '$team' not found." >&2; return 2; }
  if (( all && ${#requested[@]} > 0 )); then
    echo "error: use --all or explicit agents, not both." >&2
    return 2
  fi
  if (( ! all && ${#requested[@]} == 0 )); then
    echo "error: provide at least one agent or --all." >&2
    return 2
  fi

  local record target role rc target_json overall_ready=1
  if (( all )); then
    records=("${(@f)$(_xmux_emit_member_records "$team" 1)}")
  else
    for target in "${requested[@]}"; do
      record="$(_xmux_resolve_member_ref "$target" "$team")" || return 2
      role="$(print -r -- "$record" | awk -F'\t' '{print $3}')"
      if [[ "$role" == "lead" ]]; then
        echo "error: refusing to ensure the Codex lead pane." >&2
        return 2
      fi
      records+=("$record")
    done
  fi

  local -A seen
  local -a deduped
  local row_team row_agent key
  for record in "${records[@]}"; do
    [[ -n "$record" ]] || continue
    row_team="${record%%$'\t'*}"
    row_agent="${record#*$'\t'}"
    row_agent="${row_agent%%$'\t'*}"
    key="$row_team:$row_agent"
    [[ -n "${seen[$key]:-}" ]] && continue
    seen[$key]=1
    deduped+=("$record")
  done

  for record in "${deduped[@]}"; do
    target_json="$(_xmux_ensure_one_record "$record" "$want_bridge" "$want_ready")"
    rc=$?
    target_jsons+=("$target_json")
    (( rc == 0 )) || overall_ready=0
  done

  if (( json_output )); then
    _xmux_ensure_json "$team" "$([[ "$overall_ready" == "1" ]] && print true || print false)" "${target_jsons[@]}"
  else
    _xmux_ensure_human "$team" "$([[ "$overall_ready" == "1" ]] && print true || print false)" "${target_jsons[@]}"
  fi

  (( overall_ready == 1 )) && return 0
  return 1
}

_xmux_shutdown_agent() {
  local team="$1" target="$2"
  [[ -n "$target" ]] || { echo "error: target is required." >&2; return 1; }

  local record pane agent team_name role provider active session mode updated pane_state is_lead
  local pid_file meta_file current_pane lead_pane restore_pane cleanup_status bridge_cleanup http_cleanup bridge_cleanup_rc http_cleanup_rc
  record="$(_xmux_resolve_member_ref "$target" "$team")" || return $?
  IFS=$'\t' read -r team_name agent role provider active pane session mode updated <<< "$record"
  if [[ "$role" == "lead" ]]; then
    echo "error: refusing to shutdown the Codex lead pane via xmux shutdown --agent." >&2
    return 1
  fi

  if [[ -z "$agent" || -z "$team_name" ]]; then
    echo "error: refusing to shutdown a pane that is not tagged as an XMux teammate." >&2
    return 1
  fi

  pane_state="$(_xmux_verified_pane_state "$team_name" "$agent" "$pane")"
  if [[ "$pane_state" == "alive" ]]; then
    is_lead=$(tmux display-message -t "$pane" -p '#{@xmux-lead}' 2>/dev/null)
    if [[ "$is_lead" == "1" ]]; then
      echo "error: refusing to shutdown the Codex lead pane via xmux shutdown --agent." >&2
      return 1
    fi

    session=$(tmux display-message -t "$pane" -p '#{session_name}' 2>/dev/null)
    current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    lead_pane="$(_xmux_find_lead_pane "$team_name" "$session" 2>/dev/null)"
    restore_pane="$current_pane"
    if [[ -z "$restore_pane" || "$restore_pane" == "$pane" ]] || ! _xmux_pane_exists "$restore_pane"; then
      restore_pane="$lead_pane"
    fi
    _xmux_select_pane_if_alive "$restore_pane" || _xmux_select_pane_if_alive "$lead_pane" || true
  fi

  pid_file="$(_xmux_team_dir "$team_name")/.${agent}-bridge.pid"
  meta_file="$(_xmux_team_dir "$team_name")/.${agent}-bridge.meta"
  bridge_cleanup="$(_xmux_guarded_cleanup_pid_file "$pid_file" "$meta_file" "$team_name" "$agent" "bridge" "$team_name:$agent bridge" 2>/dev/null)"
  bridge_cleanup_rc=$?

  local http_pid_file
  http_pid_file="$(_xmux_team_dir "$team_name")/.${agent}-mcp-http.pid"
  local http_meta_file
  http_meta_file="$(_xmux_http_mcp_metadata_file "$http_pid_file")"
  http_cleanup="$(_xmux_guarded_cleanup_pid_file "$http_pid_file" "$http_meta_file" "$team_name" "$agent" "http_mcp" "$team_name:$agent http mcp" 2>/dev/null)"
  http_cleanup_rc=$?
  if (( bridge_cleanup_rc != 0 || http_cleanup_rc != 0 )); then
    echo "[xmux] error: failed to stop verified helper for $team_name:$agent cleanup:bridge=${bridge_cleanup:-none} http=${http_cleanup:-none}" >&2
    return 1
  fi
  rm -f "$(_xmux_team_dir "$team_name")/.${agent}-mcp-http.url"

  if [[ "$pane_state" == "alive" ]]; then
    tmux kill-pane -t "$pane" || return 1
  fi
  _xmux_mark_member_inactive "$team_name" "$agent" || true
  if [[ "$pane_state" == "alive" ]]; then
    _xmux_select_pane_if_alive "$restore_pane" || _xmux_select_pane_if_alive "$lead_pane" || true
    echo "[xmux] shutdown ${agent:-$pane} pane:$pane team:${team_name:-unknown} cleanup:bridge=${bridge_cleanup:-none} http=${http_cleanup:-none}"
  else
    echo "[xmux] shutdown ${agent:-$pane} pane:${pane:-none} team:${team_name:-unknown} (pane already $pane_state) cleanup:bridge=${bridge_cleanup:-none} http=${http_cleanup:-none}"
  fi
}

_xmux_cmd_shutdown() {
  local team="" timeout=5 archive=1 reason="manual-shutdown" lead_already_exiting=0 arg
  local -a requested_agents
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 ]] || { echo "error: --timeout requires seconds." >&2; return 1; }
        timeout="$2"
        shift 2
        ;;
      --agent)
        [[ $# -ge 2 ]] || { echo "error: --agent requires an agent name." >&2; return 1; }
        requested_agents+=("$2")
        shift 2
        ;;
      --no-archive)
        archive=0
        shift
        ;;
      --reason)
        [[ $# -ge 2 ]] || { echo "error: --reason requires a reason." >&2; return 1; }
        reason="$2"
        shift 2
        ;;
      --lead-already-exiting)
        lead_already_exiting=1
        shift
        ;;
      -h|--help)
        echo "Usage: xmux shutdown -t <team> [--agent <agent> ...] [--timeout <seconds>] [--no-archive] [--reason <reason>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        echo "error: unexpected argument '$arg'" >&2
        return 1
        ;;
    esac
  done

  [[ -n "$team" ]] || { echo "error: -t <team> is required for shutdown scope." >&2; return 1; }
  _xmux_validate_team_name "$team" || return 1
  [[ "$timeout" == <-> ]] || { echo "error: --timeout must be a non-negative integer." >&2; return 1; }

  local team_dir
  team_dir="$(_xmux_team_dir "$team")"
  [[ -f "$team_dir/team.json" ]] || { echo "error: XMux team '$team' does not exist at $team_dir." >&2; return 1; }

  if (( ${#requested_agents[@]} > 0 )); then
    local target failed_csv failed_text
    local -a failed_agents=()
    for target in "${requested_agents[@]}"; do
      _xmux_shutdown_agent "$team" "$target" || failed_agents+=("$target")
    done
    if (( ${#failed_agents[@]} > 0 )); then
      failed_csv="${(j:,:)failed_agents}"
      failed_text="${(j:, :)failed_agents}"
      echo "error: teammate shutdown incomplete for team:$team; failed agents: $failed_text" >&2
      echo "       Team state was not archived. Requests and inbox history remain at $team_dir." >&2
      return 1
    fi
    echo "[xmux] shutdown complete team:$team agents:${(j:,:)requested_agents} archived:false reason:$reason"
    return 0
  fi

  _xmux_mark_team_shutdown_start "$team" "$reason" || return 1

  local row_team name role provider active pane session mode updated
  local -a failed_agents=()
  while IFS=$'\t' read -r row_team name role provider active pane session mode updated; do
    [[ -z "$name" || "$role" == "lead" ]] && continue
    _xmux_shutdown_teammate "$team" "$name" "$provider" "$pane" "$timeout" || failed_agents+=("$name")
  done < <(_xmux_emit_team_members "$team")

  if (( ${#failed_agents[@]} > 0 )); then
    local failed_csv failed_text
    failed_csv="${(j:,:)failed_agents}"
    failed_text="${(j:, :)failed_agents}"
    _xmux_mark_team_shutdown_degraded "$team" "$reason" "$failed_csv" || true
    echo "error: shutdown incomplete for team:$team; failed agents: $failed_text" >&2
    echo "       Team state was not archived. Requests and inbox history remain at $team_dir." >&2
    return 1
  fi

  _xmux_clear_team_tmux_metadata "$team" || true

  if (( archive )); then
    local archive_dir
    archive_dir="$(_xmux_archive_team_dir "$team" "$reason")" || return 1
    echo "[xmux] shutdown complete team:$team archived:$archive_dir reason:$reason"
  else
    _xmux_mark_team_shutdown_complete "$team" "$reason" "shutdown" "" || return 1
    echo "[xmux] shutdown complete team:$team archived:false reason:$reason"
  fi
}

_xmux_cmd_recover() {
  local team="" target="" session="" provider="" action="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -s|--session)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a session name." >&2; return 1; }
        session="$2"
        shift 2
        ;;
      --provider)
        [[ $# -ge 2 ]] || { echo "error: --provider requires a provider." >&2; return 1; }
        provider="$2"
        shift 2
        ;;
      --restart-bridge)
        [[ -z "$action" ]] || { echo "error: choose one recovery action." >&2; return 1; }
        action="restart-bridge"
        shift
        ;;
      --restart|--restart-teammate)
        [[ -z "$action" ]] || { echo "error: choose one recovery action." >&2; return 1; }
        action="restart-teammate"
        shift
        ;;
      -h|--help)
        echo "Usage: xmux recover -t <team> <agent> --restart-bridge|--restart-teammate [--session <session>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        [[ -z "$target" ]] || { echo "error: extra argument '$arg'" >&2; return 1; }
        target="$arg"
        shift
        ;;
    esac
  done

  if [[ "$target" == *:* ]]; then
    local target_team="${target%%:*}"
    local target_agent="${target#*:}"
    if [[ -n "$team" && "$team" != "$target_team" ]]; then
      echo "error: target team '$target_team' conflicts with -t '$team'." >&2
      return 1
    fi
    team="$target_team"
    target="$target_agent"
  fi

  [[ -n "$team" ]] || { echo "error: -t <team> is required for recovery scope." >&2; return 1; }
  [[ -n "$target" ]] || { echo "error: agent is required for recovery scope." >&2; return 1; }
  [[ -n "$action" ]] || { echo "error: choose --restart-bridge or --restart-teammate." >&2; return 1; }
  _xmux_validate_team_name "$team" || return 1
  _xmux_require_tmux || return 1

  [[ -n "$provider" ]] || provider="$(_xmux_member_field "$team" "$target" provider 2>/dev/null)"
  case "$provider" in
    claude|gemini|copilot) ;;
    "") echo "error: cannot determine provider for $team:$target; pass --provider." >&2; return 1 ;;
    *) echo "error: unsupported provider '$provider' for recovery." >&2; return 1 ;;
  esac

  local team_dir pane timeout idle_pattern submit_delay env_file pane_state
  local bridge_pid_file bridge_meta_file http_pid_file http_meta_file cleanup_status cleanup_rc
  team_dir="$(_xmux_team_dir "$team")"
  env_file="$team_dir/.bridge-${target}.env"
  bridge_pid_file="$team_dir/.${target}-bridge.pid"
  bridge_meta_file="$team_dir/.${target}-bridge.meta"
  http_pid_file="$team_dir/.${target}-mcp-http.pid"
  http_meta_file="$(_xmux_http_mcp_metadata_file "$http_pid_file")"
  pane="$(_xmux_member_field "$team" "$target" pane 2>/dev/null)"
  timeout=60
  idle_pattern="$(_xmux_bridge_env_value "$env_file" XMUX_IDLE_PATTERN 2>/dev/null)"
  [[ -z "$idle_pattern" ]] && idle_pattern="$(_xmux_provider_idle_pattern "$provider")"
  submit_delay="$(_xmux_bridge_env_value "$env_file" XMUX_SUBMIT_DELAY 2>/dev/null)"
  [[ -z "$submit_delay" ]] && submit_delay="$(_xmux_provider_submit_delay "$provider")"

  if [[ "$action" == "restart-bridge" ]]; then
    pane_state="$(_xmux_verified_pane_state "$team" "$target" "$pane")"
    if [[ "$pane_state" != "alive" ]]; then
      echo "error: cannot restart bridge because $team:$target has no live pane." >&2
      return 1
    fi
    cleanup_status="$(_xmux_guarded_cleanup_pid_file "$bridge_pid_file" "$bridge_meta_file" "$team" "$target" "bridge" "$team:$target bridge" 2>/dev/null)"
    cleanup_rc=$?
    (( cleanup_rc == 0 )) || { echo "error: failed to stop verified bridge for $team:$target." >&2; return 1; }
    _xmux_start_member_bridge "$team" "$target" "$provider" "$pane" "$timeout" "$idle_pattern" "$submit_delay" || return 1
    echo "[xmux] restarted bridge for $team:$target pane:$pane cleanup:bridge=${cleanup_status:-none}"
    return 0
  fi

  [[ -n "$session" ]] || session="$(_xmux_session_for_team "$team")"
  [[ -n "$session" ]] || { echo "error: cannot determine tmux session for team '$team'; pass --session." >&2; return 1; }
  _xmux_validate_session_name "$session" || return 1

  if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
    _xmux_shutdown_agent "$team" "$target" || return 1
  else
    _xmux_guarded_cleanup_pid_file "$bridge_pid_file" "$bridge_meta_file" "$team" "$target" "bridge" "$team:$target bridge" >/dev/null 2>&1 \
      || { echo "error: failed to stop verified bridge for $team:$target." >&2; return 1; }
    _xmux_guarded_cleanup_pid_file "$http_pid_file" "$http_meta_file" "$team" "$target" "http_mcp" "$team:$target http mcp" >/dev/null 2>&1 \
      || { echo "error: failed to stop verified HTTP MCP for $team:$target." >&2; return 1; }
    _xmux_mark_member_inactive "$team" "$target" || true
  fi

  _xmux_start_provider_member "$provider" "$team" "$target" "$session"
}

_xmux_cmd_submit_test() {
  local team="" target="" text="/help" delay="" force=0 custom_text=0 arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      --text)
        [[ $# -ge 2 ]] || { echo "error: --text requires text." >&2; return 1; }
        text="$2"
        custom_text=1
        shift 2
        ;;
      --delay)
        [[ $# -ge 2 ]] || { echo "error: --delay requires seconds." >&2; return 1; }
        delay="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      -h|--help)
        echo "Usage: xmux submit-test -t <team> <agent> [--text <text>] [--delay <seconds>] [--force]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        [[ -z "$target" ]] || { echo "error: extra argument '$arg'" >&2; return 1; }
        target="$arg"
        shift
        ;;
    esac
  done

  if [[ "$target" == *:* ]]; then
    local target_team="${target%%:*}"
    local target_agent="${target#*:}"
    if [[ -n "$team" && "$team" != "$target_team" ]]; then
      echo "error: target team '$target_team' conflicts with -t '$team'." >&2
      return 1
    fi
    team="$target_team"
    target="$target_agent"
  fi

  [[ -n "$team" ]] || { echo "error: -t <team> is required for submit-test scope." >&2; return 1; }
  [[ -n "$target" ]] || { echo "error: agent is required for submit-test scope." >&2; return 1; }
  _xmux_validate_team_name "$team" || return 1
  _xmux_require_tmux || return 1

  local first_char
  first_char=$(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1)
  if (( custom_text )) && [[ "$first_char" != "/" && "$force" -eq 0 ]]; then
    echo "error: custom submit-test text must start with '/' or use --force." >&2
    return 1
  fi

  local provider pane buf submit_buf
  provider="$(_xmux_member_field "$team" "$target" provider 2>/dev/null)"
  [[ -z "$delay" ]] && delay="$(_xmux_provider_submit_delay "$provider")"
  pane="$(_xmux_resolve_target_to_pane "$target" "$team")" || return $?

  buf="xmux-submit-test-$$-$RANDOM"
  submit_buf="xmux-submit-cr-$$-$RANDOM"
  if ! printf '%s' "$text" | tmux load-buffer -b "$buf" - 2>/dev/null; then
    echo "error: failed to load submit-test buffer." >&2
    return 1
  fi
  if [[ "$provider" == "copilot" ]]; then
    tmux send-keys -t "$pane" Escape '[' I 2>/dev/null || { tmux delete-buffer -b "$buf" 2>/dev/null; return 1; }
    sleep 0.05
  fi
  if ! tmux paste-buffer -d -p -b "$buf" -t "$pane" 2>/dev/null; then
    tmux delete-buffer -b "$buf" 2>/dev/null
    echo "error: failed to paste submit-test text to $team:$target." >&2
    return 1
  fi
  tmux delete-buffer -b "$buf" 2>/dev/null

  sleep "$delay"
  if [[ "$provider" == "copilot" ]]; then
    tmux send-keys -t "$pane" Escape '[' I 2>/dev/null || return 1
    sleep 0.05
  fi
  if ! printf '\r' | tmux load-buffer -b "$submit_buf" - 2>/dev/null; then
    echo "error: failed to load submit carriage-return buffer." >&2
    return 1
  fi
  if ! tmux paste-buffer -d -b "$submit_buf" -t "$pane" 2>/dev/null; then
    tmux delete-buffer -b "$submit_buf" 2>/dev/null
    echo "error: failed to paste submit carriage return to $team:$target." >&2
    return 1
  fi
  tmux delete-buffer -b "$submit_buf" 2>/dev/null
  echo "[xmux] submit-test sent ${#text} chars plus raw carriage return to $team:$target pane:$pane"
}

_xmux_prepare_codex_runtime() {
  if [[ -f "$XMUX_INSTALL_DIR/scripts/setup_xmux_codex_mcp.py" ]]; then
    python3 "$XMUX_INSTALL_DIR/scripts/setup_xmux_codex_mcp.py" \
      --doctor \
      --quiet \
      --xmux-install-dir "$XMUX_INSTALL_DIR" \
      --server-path "$XMUX_INSTALL_DIR/xmux-lead-mcp-server.js" >/dev/null 2>&1 || {
        echo "[xmux] warning: XMux Codex integration is not configured; run 'xmux setup-codex'." >&2
      }
  fi
}

_xmux_codex_setup_script() {
  local script="$XMUX_INSTALL_DIR/scripts/setup_xmux_codex_mcp.py"
  [[ -f "$script" ]] || {
    echo "error: missing XMux Codex setup script at $script." >&2
    return 1
  }
  print -r -- "$script"
}

_xmux_run_codex_setup_script() {
  local script
  script="$(_xmux_codex_setup_script)" || return 1
  python3 "$script" \
    --xmux-install-dir "$XMUX_INSTALL_DIR" \
    --server-path "$XMUX_INSTALL_DIR/xmux-lead-mcp-server.js" \
    "$@"
}

_xmux_setup_codex_usage() {
  cat >&2 <<'EOF'
Usage: xmux setup-codex [--skills-dir <dir>] [--without-skills]
       xmux doctor-codex
       xmux remove-codex
EOF
}

_xmux_cmd_setup_codex() {
  local arg
  local -a setup_args=()
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --without-skills)
        setup_args+=("$arg")
        shift
        ;;
      --home|--project|--skills-dir)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a path." >&2; return 1; }
        setup_args+=("$arg" "$2")
        shift 2
        ;;
      -h|--help)
        _xmux_setup_codex_usage
        return 0
        ;;
      *)
        echo "error: unknown setup-codex option '$arg'." >&2
        _xmux_setup_codex_usage
        return 1
        ;;
    esac
  done
  _xmux_run_codex_setup_script "${setup_args[@]}"
}

_xmux_cmd_doctor_codex() {
  local arg
  local -a doctor_args=(--doctor)
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --quiet)
        doctor_args+=("$arg")
        shift
        ;;
      --home|--project|--skills-dir)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a path." >&2; return 1; }
        doctor_args+=("$arg" "$2")
        shift 2
        ;;
      -h|--help)
        _xmux_setup_codex_usage
        return 0
        ;;
      *)
        echo "error: unknown doctor-codex option '$arg'." >&2
        _xmux_setup_codex_usage
        return 1
        ;;
    esac
  done
  _xmux_run_codex_setup_script "${doctor_args[@]}"
}

_xmux_cmd_remove_codex() {
  local arg
  local -a remove_args=(--remove)
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --home|--project)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a path." >&2; return 1; }
        remove_args+=("$arg" "$2")
        shift 2
        ;;
      -h|--help)
        _xmux_setup_codex_usage
        return 0
        ;;
      *)
        echo "error: unknown remove-codex option '$arg'." >&2
        _xmux_setup_codex_usage
        return 1
        ;;
    esac
  done
  _xmux_run_codex_setup_script "${remove_args[@]}"
}

_xmux_shutdown_on_lead_exit_enabled() {
  local value="${1:-1}"
  case "$value" in
    0|false|FALSE|no|NO|off|OFF)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

_xmux_lead_stdio_is_tty() {
  [[ -t 0 && -t 1 ]]
}

_xmux_run_codex_lead() {
  local codex_home_env rc lead_stdio_ready=0
  codex_home_env="$(_xmux_codex_home_env_name)"
  _xmux_lead_stdio_is_tty && lead_stdio_ready=1
  env -u "$codex_home_env" -u XMUX_DIR -u XMUX_HOME \
    XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    XMUX_TEAM="$XMUX_TEAM" \
    XMUX_AGENT="${XMUX_AGENT:-$XMUX_LEAD_AGENT}" \
    XMUX_TEAM_DIR="$XMUX_TEAM_DIR" \
    codex "$@"
  rc=$?

  if _xmux_shutdown_on_lead_exit_enabled "${XMUX_SHUTDOWN_ON_LEAD_EXIT:-1}" && [[ -n "${XMUX_TEAM:-}" ]]; then
    if (( lead_stdio_ready )); then
      xmux shutdown -t "$XMUX_TEAM" --reason lead-exit --lead-already-exiting || {
        echo "[xmux] warning: automatic shutdown failed for team:$XMUX_TEAM" >&2
      }
    else
      echo "[xmux] warning: skipping automatic shutdown for team:$XMUX_TEAM because the lead did not start with terminal stdio." >&2
    fi
  fi
  return "$rc"
}

_xmux_build_codex_env_command() {
  local team_name="$1" team_dir="$2"
  shift 2
  local shutdown_on_exit=1
  if [[ $# -gt 0 && "${1:-}" != "--" ]]; then
    shutdown_on_exit="${1:-1}"
    shift
  fi
  [[ "${1:-}" == "--" ]] && shift
  local codex_cmd arg codex_home_env env_prefix wrapper
  codex_home_env="$(_xmux_codex_home_env_name)"
  env_prefix="$(_xmux_runtime_env_assignments)"
  wrapper='source "$XMUX_INSTALL_DIR/xmux.zsh"; _xmux_run_codex_lead "$@"'
  codex_cmd="exec env -u $(_xmux_q "$codex_home_env") -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_TEAM=$(_xmux_q "$team_name") XMUX_AGENT=$(_xmux_q "$XMUX_LEAD_AGENT") XMUX_TEAM_DIR=$(_xmux_q "$team_dir") XMUX_SHUTDOWN_ON_LEAD_EXIT=$(_xmux_q "$shutdown_on_exit") zsh -lc $(_xmux_q "$wrapper") xmux-lead"
  for arg in "$@"; do
    codex_cmd+=" $(_xmux_q "$arg")"
  done
  print -r -- "$codex_cmd"
}

_xmux_spawn_member() {
  _xmux_refresh_home
  local provider="$1" default_agent="$2" idle_pattern="$3" border_color="$4" base_cmd="$5"
  shift 5

  local team="" agent="$default_agent" timeout=60 session=""
  local submit_delay="${XMUX_SUBMIT_DELAY:-0.2}"
  [[ "$provider" == "copilot" && -z "${XMUX_SUBMIT_DELAY:-}" ]] && submit_delay=0.8
  local -a provider_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|-T)
        [[ $# -ge 2 ]] || { echo "error: $1 requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -n)
        [[ $# -ge 2 ]] || { echo "error: -n requires an agent name." >&2; return 1; }
        agent="$2"
        shift 2
        ;;
      -x)
        [[ $# -ge 2 ]] || { echo "error: -x requires a timeout." >&2; return 1; }
        timeout="$2"
        shift 2
        ;;
      -s|--session)
        [[ $# -ge 2 ]] || { echo "error: $1 requires a tmux session name." >&2; return 1; }
        session="$2"
        shift 2
        ;;
      -h|--help)
        _xmux_member_usage "xmux ${provider}"
        return 0
        ;;
      --)
        shift
        provider_args+=("$@")
        break
        ;;
      *)
        provider_args+=("$1")
        shift
        ;;
    esac
  done

  _xmux_require_tmux || return 1
  command -v "${base_cmd%% *}" &>/dev/null || { echo "error: ${base_cmd%% *} CLI not found in PATH." >&2; return 1; }

  [[ -z "$team" ]] && team="$(_xmux_current_team)"
  [[ -z "$team" ]] && { _xmux_member_usage "xmux-${provider}"; return 1; }
  _xmux_validate_team_name "$team" || return 1

  local team_dir inbox outbox
  team_dir="$(_xmux_team_dir "$team")"
  inbox="$team_dir/inboxes/$agent.json"
  outbox="$team_dir/inboxes/$XMUX_LEAD_AGENT.json"
  [[ -d "$team_dir" ]] || { echo "error: XMux team '$team' does not exist at $team_dir." >&2; return 1; }

  if [[ -z "$session" ]]; then
    if [[ -n "$TMUX" ]]; then
      session=$(tmux display-message -p '#S' 2>/dev/null)
    else
      session=$(tmux list-sessions -F '#S' 2>/dev/null | while read -r s; do
        [[ "$s" == *:* || "$s" == *.* || "$s" == */* ]] && continue
        [[ "$(tmux show-option -v -t "$s" @xmux-team 2>/dev/null)" == "$team" ]] && { print -r -- "$s"; break; }
      done)
    fi
  fi
  [[ -n "$session" ]] || { echo "error: cannot determine tmux session for team '$team'." >&2; return 1; }
  _xmux_validate_session_name "$session" || return 1

  local lead_pane
  lead_pane="$(_xmux_find_lead_pane "$team" "$session")"
  [[ -n "$lead_pane" ]] || { echo "error: cannot find lead pane for team '$team'." >&2; return 1; }

  _xmux_ensure_team_files "$team"
  [[ -f "$inbox" ]] || print -r -- '[]' > "$inbox"
  [[ -f "$outbox" ]] || print -r -- '[]' > "$outbox"

  if [[ "$provider" == "copilot" ]]; then
    _xmux_start_copilot_mcp "$team" "$agent" "$outbox" || {
      echo "error: failed to start Copilot MCP HTTP bridge." >&2
      return 1
    }
  fi
  if [[ "$provider" == "gemini" ]]; then
    _xmux_prepare_gemini_mcp || {
      echo "error: failed to configure Gemini MCP bridge in ~/.gemini/settings.json." >&2
      return 1
    }
  fi

  local cli_cmd="$base_cmd"
  local arg
  for arg in "${provider_args[@]}"; do
    cli_cmd+=" $(_xmux_q "$arg")"
  done

  local pane_count agent_pane split_target
  pane_count=$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
  local env_cmd env_prefix provider_env_assignments
  env_prefix="$(_xmux_runtime_env_assignments)"
  provider_env_assignments="$(_xmux_provider_env_assignments "$provider" "${provider_args[@]}")"
  env_cmd="exec env -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_OUTBOX=$(_xmux_q "$outbox") XMUX_AGENT=$(_xmux_q "$agent") XMUX_TEAM=$(_xmux_q "$team") $cli_cmd"
  if [[ -n "$provider_env_assignments" ]]; then
    env_cmd="exec env -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_OUTBOX=$(_xmux_q "$outbox") XMUX_AGENT=$(_xmux_q "$agent") XMUX_TEAM=$(_xmux_q "$team") $provider_env_assignments $cli_cmd"
  fi

  if (( pane_count <= 1 )); then
    agent_pane=$(tmux split-window -t "$lead_pane" -h -P -F '#{pane_id}' "$env_cmd")
    tmux resize-pane -t "$agent_pane" -x 70% 2>/dev/null
  else
    split_target=$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null | grep -v "^${lead_pane}$" | tail -1)
    [[ -z "$split_target" ]] && split_target="$lead_pane"
    agent_pane=$(tmux split-window -t "$split_target" -v -P -F '#{pane_id}' "$env_cmd")
  fi
  [[ -n "$agent_pane" ]] || { echo "error: failed to create teammate pane." >&2; return 1; }

  tmux set-option -p -t "$agent_pane" allow-rename off 2>/dev/null
  tmux select-pane -t "$agent_pane" -T "$agent" 2>/dev/null
  tmux set-option -p -t "$agent_pane" @agent_name "$agent" 2>/dev/null
  tmux set-option -p -t "$agent_pane" pane-border-format "#[fg=${border_color},bold] #{@agent_name} #[default]" 2>/dev/null
  tmux set-option -p -t "$agent_pane" @xmux-agent "$agent" 2>/dev/null
  tmux set-option -p -t "$agent_pane" @xmux-team "$team" 2>/dev/null
  tmux set-option -p -t "$agent_pane" @xmux-bridge "1" 2>/dev/null
  tmux select-pane -t "$lead_pane" 2>/dev/null

  _xmux_register_member "$team" "$agent" "$provider" "$agent_pane"
  _xmux_start_member_bridge "$team" "$agent" "$provider" "$agent_pane" "$timeout" "$idle_pattern" "$submit_delay" || return 1

  echo "[xmux-${provider}] $agent attached - pane:$agent_pane team:$team"
}

xmux-claude() {
  _xmux_spawn_member claude claude-worker "" colour141 "claude" "$@"
}

xmux-gemini() {
  _xmux_spawn_member gemini gemini-worker "Type your message" colour33 "gemini --yolo" "$@"
}

xmux-copilot() {
  _xmux_spawn_member copilot copilot-worker "/ commands" colour98 "copilot --yolo --autopilot --max-autopilot-continues 10" "$@"
}

_xmux_start() {
  _xmux_refresh_home
  local session_name="" team_name=""
  local spawn_claude=0 spawn_gemini=0 spawn_copilot=0
  local shutdown_on_lead_exit="${XMUX_SHUTDOWN_ON_LEAD_EXIT:-1}"
  local -a codex_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        [[ $# -ge 2 ]] || { echo "error: -n requires a session name." >&2; return 1; }
        session_name="$2"
        shift 2
        ;;
      -T)
        [[ $# -ge 2 ]] || { echo "error: -T requires a team name." >&2; return 1; }
        team_name="$2"
        shift 2
        ;;
      --claude)
        spawn_claude=1
        shift
        ;;
      --gemini)
        spawn_gemini=1
        shift
        ;;
      --copilot)
        spawn_copilot=1
        shift
        ;;
      --shutdown-on-lead-exit)
        shutdown_on_lead_exit=1
        shift
        ;;
      --keep-team-on-lead-exit|--no-shutdown-on-lead-exit)
        shutdown_on_lead_exit=0
        shift
        ;;
      --codex|-c|codex|codex-"worker")
        echo "error: Codex teammates are unsupported in XMux; Codex is the lead only. Use xmux claude, xmux gemini, or xmux copilot." >&2
        return 1
        ;;
      --)
        shift
        codex_args+=("$@")
        break
        ;;
      -h|--help)
        _xmux_usage
        return 0
        ;;
      *)
        codex_args+=("$1")
        shift
        ;;
    esac
  done

  [[ -z "$session_name" ]] && session_name="$(_xmux_default_session_name)"
  [[ -z "$team_name" ]] && team_name="$(_xmux_team_from_session "$session_name")"
  _xmux_validate_session_name "$session_name" || return 1
  _xmux_validate_team_name "$team_name" || return 1

  _xmux_require_tmux || return 1
  command -v codex &>/dev/null || { echo "error: codex is not installed." >&2; return 1; }

  local team_dir codex_cmd
  team_dir="$(_xmux_team_dir "$team_name")"
  _xmux_prepare_codex_runtime

  if [[ -n "$TMUX" ]] && _xmux_lead_stdio_is_tty; then
    local session lead_pane
    session=$(tmux display-message -p '#S' 2>/dev/null)
    _xmux_validate_session_name "$session" || return 1
    lead_pane="$TMUX_PANE"
    _xmux_mailbox_init_team "$team_name" "$lead_pane" "$session"

    (( spawn_claude )) && xmux-claude -t "$team_name"
    (( spawn_gemini )) && xmux-gemini -t "$team_name"
    (( spawn_copilot )) && xmux-copilot -t "$team_name"

    XMUX_TEAM="$team_name" \
      XMUX_AGENT="$XMUX_LEAD_AGENT" \
      XMUX_TEAM_DIR="$team_dir" \
      XMUX_SHUTDOWN_ON_LEAD_EXIT="$shutdown_on_lead_exit" \
      _xmux_run_codex_lead "${codex_args[@]}"
    return
  fi

  codex_cmd="$(_xmux_build_codex_env_command "$team_name" "$team_dir" "$shutdown_on_lead_exit" -- "${codex_args[@]}")"

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    local window_name
    window_name=$(git symbolic-ref --short HEAD 2>/dev/null || basename "$PWD")
    if ! tmux new-session -d -s "$session_name" -n "$window_name" -c "$PWD" "$codex_cmd"; then
      echo "error: failed to create tmux session '$session_name'." >&2
      return 1
    fi
  fi

  local lead_pane
  lead_pane="$(_xmux_find_lead_pane "$team_name" "$session_name")"
  [[ -n "$lead_pane" ]] || { echo "error: cannot find lead pane for session '$session_name'." >&2; return 1; }
  _xmux_mailbox_init_team "$team_name" "$lead_pane" "$session_name"

  (( spawn_claude )) && _xmux_spawn_member claude claude-worker "" colour141 "claude" -t "$team_name" -s "$session_name"
  (( spawn_gemini )) && _xmux_spawn_member gemini gemini-worker "Type your message" colour33 "gemini --yolo" -t "$team_name" -s "$session_name"
  (( spawn_copilot )) && _xmux_spawn_member copilot copilot-worker "/ commands" colour98 "copilot --yolo --autopilot --max-autopilot-continues 10" -t "$team_name" -s "$session_name"

  if _xmux_lead_stdio_is_tty; then
    tmux attach-session -t "$session_name"
  else
    echo "[xmux] team created team:$team_name session:$session_name detached:true"
  fi
}

_xmux_expand_provider_list() {
  local raw="$1" provider normalized
  if [[ "$raw" == *,* ]]; then
    echo "error: provider names must be space-separated; use 'gemini copilot', not 'gemini,copilot'." >&2
    return 1
  fi
  for provider in ${(s: :)raw}; do
    [[ -n "$provider" ]] || continue
    case "${provider:l}" in
      claude|gemini|copilot)
        normalized="${provider:l}"
        ;;
      *)
        echo "error: unsupported provider '$provider'. Use claude, gemini, or copilot." >&2
        return 1
        ;;
    esac
    print -r -- "$normalized"
  done
}

_xmux_provider_start_flag() {
  case "$1" in
    claude) print -r -- "--claude" ;;
    gemini) print -r -- "--gemini" ;;
    copilot) print -r -- "--copilot" ;;
    *) echo "error: unsupported provider '$1'. Use claude, gemini, or copilot." >&2; return 1 ;;
  esac
}

_xmux_spawn_default_provider_member() {
  local provider="$1" team="$2" session="$3"
  local -a args
  args=(-t "$team")
  [[ -n "$session" ]] && args+=(-s "$session")
  case "$provider" in
    claude) xmux-claude "${args[@]}" ;;
    gemini) xmux-gemini "${args[@]}" ;;
    copilot) xmux-copilot "${args[@]}" ;;
    *) echo "error: unsupported provider '$provider'. Use claude, gemini, or copilot." >&2; return 1 ;;
  esac
}

_xmux_cmd_team_create() {
  local team="" session="" shutdown_flag="" arg provider flag expanded
  local -a providers codex_args start_args expanded_providers
  local -A seen

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
	      -n|-s|--session)
	        [[ $# -ge 2 ]] || { echo "error: $arg requires a session name." >&2; return 1; }
	        session="$2"
	        shift 2
	        ;;
	      --with)
	        [[ $# -ge 2 ]] || { echo "error: --with requires a provider list." >&2; return 1; }
	        shift
	        local consumed=0
	        while [[ $# -gt 0 ]]; do
	          case "$1" in
	            --|-*)
	              break
	              ;;
	            *)
	              expanded="$(_xmux_expand_provider_list "$1")" || return 1
	              expanded_providers=("${(@f)expanded}")
	              providers+=("${expanded_providers[@]}")
	              consumed=1
	              shift
	              ;;
	          esac
	        done
	        (( consumed )) || { echo "error: --with requires at least one provider." >&2; return 1; }
	        ;;
	      --claude|--gemini|--copilot)
	        providers+=("${arg#--}")
	        shift
        ;;
      --shutdown-on-lead-exit)
        shutdown_flag="--shutdown-on-lead-exit"
        shift
        ;;
      --keep-team-on-lead-exit|--no-shutdown-on-lead-exit)
        shutdown_flag="--keep-team-on-lead-exit"
        shift
        ;;
      --)
        shift
        codex_args+=("$@")
        break
        ;;
      -h|--help)
        echo "Usage: xmux teamCreate -t <team> [-n <session_name>] [claude|gemini|copilot ...] [--shutdown-on-lead-exit|--keep-team-on-lead-exit] [--] [codex args...]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        expanded="$(_xmux_expand_provider_list "$arg")" || return 1
        expanded_providers=("${(@f)expanded}")
        providers+=("${expanded_providers[@]}")
        shift
        ;;
    esac
  done

  [[ -n "$team" ]] || { echo "error: -t <team> is required for teamCreate." >&2; return 1; }
  start_args=(-T "$team")
  [[ -n "$session" ]] && start_args=(-n "$session" "${start_args[@]}")
  [[ -n "$shutdown_flag" ]] && start_args+=("$shutdown_flag")

  for provider in "${providers[@]}"; do
    [[ -n "${seen[$provider]:-}" ]] && continue
    seen[$provider]=1
    flag="$(_xmux_provider_start_flag "$provider")" || return 1
    start_args+=("$flag")
  done

  (( ${#codex_args[@]} > 0 )) && start_args+=(-- "${codex_args[@]}")
  _xmux_start "${start_args[@]}"
}

_xmux_cmd_teammate_add() {
  local team="" session="" arg provider expanded
  local -a providers expanded_providers
  local -A seen

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -s|--session)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a session name." >&2; return 1; }
        session="$2"
        shift 2
        ;;
      --with)
        [[ $# -ge 2 ]] || { echo "error: --with requires a provider list." >&2; return 1; }
        shift
        local consumed=0
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --|-*)
              break
              ;;
            *)
              expanded="$(_xmux_expand_provider_list "$1")" || return 1
              expanded_providers=("${(@f)expanded}")
              providers+=("${expanded_providers[@]}")
              consumed=1
              shift
              ;;
          esac
        done
        (( consumed )) || { echo "error: --with requires at least one provider." >&2; return 1; }
        ;;
      -h|--help)
        echo "Usage: xmux teammateAdd -t <team> [--session <session_name>] <claude|gemini|copilot>..."
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        expanded="$(_xmux_expand_provider_list "$arg")" || return 1
        expanded_providers=("${(@f)expanded}")
        providers+=("${expanded_providers[@]}")
        shift
        ;;
    esac
  done

  [[ -n "$team" ]] || team="$(_xmux_current_team)"
  [[ -n "$team" ]] || { echo "error: -t <team> is required for teammateAdd outside an XMux team." >&2; return 1; }
  _xmux_validate_team_name "$team" || return 1
  if [[ -n "$session" ]]; then
    _xmux_validate_session_name "$session" || return 1
  fi
  (( ${#providers[@]} > 0 )) || { echo "error: provide at least one provider: claude, gemini, or copilot." >&2; return 1; }

  for provider in "${providers[@]}"; do
    [[ -n "${seen[$provider]:-}" ]] && continue
    seen[$provider]=1
    _xmux_spawn_default_provider_member "$provider" "$team" "$session" || return 1
  done
}

_xmux_cmd_team_status() {
  local team="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux teamStatus [-t <team>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        echo "error: unexpected argument '$arg'" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$team" ]]; then
    team="$(_xmux_current_team)"
  fi
  [[ -n "$team" ]] || {
    echo "error: cannot determine current XMux team; run from an XMux pane or pass -t <team>." >&2
    return 1
  }
  _xmux_cmd_teammates -t "$team"
}

_xmux_cmd_teammate_status() {
  local team="" target="" arg
  local -a bridge_args
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux teammateStatus -t <team> [<agent>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        [[ -z "$target" ]] || { echo "error: extra argument '$arg'" >&2; return 1; }
        target="$arg"
        shift
        ;;
    esac
  done

  if [[ "$target" == *:* ]]; then
    local target_team="${target%%:*}"
    local target_agent="${target#*:}"
    if [[ -n "$team" && "$team" != "$target_team" ]]; then
      echo "error: target team '$target_team' conflicts with -t '$team'." >&2
      return 1
    fi
    team="$target_team"
    target="$target_agent"
  fi

  [[ -n "$team" ]] || { echo "error: -t <team> is required for teammateStatus." >&2; return 1; }
  bridge_args=(-t "$team")
  [[ -n "$target" ]] && bridge_args+=("$target")
  _xmux_cmd_bridge_status "${bridge_args[@]}"
}

_xmux_cmd_teammate_shutdown() {
  local team="" timeout="" reason="" arg target target_team target_agent
  local -a targets shutdown_args

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -t|-T|--team)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a team name." >&2; return 1; }
        team="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 ]] || { echo "error: --timeout requires seconds." >&2; return 1; }
        timeout="$2"
        shift 2
        ;;
      --reason)
        [[ $# -ge 2 ]] || { echo "error: --reason requires a reason." >&2; return 1; }
        reason="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux teammateShutdown -t <team> <agent>... [--timeout <seconds>] [--reason <reason>]"
        return 0
        ;;
      -*)
        echo "error: unknown option '$arg'" >&2
        return 1
        ;;
      *)
        targets+=("$arg")
        shift
        ;;
    esac
  done

  for target in "${targets[@]}"; do
    if [[ "$target" == *:* ]]; then
      target_team="${target%%:*}"
      target_agent="${target#*:}"
      if [[ -n "$team" && "$team" != "$target_team" ]]; then
        echo "error: target team '$target_team' conflicts with -t '$team'." >&2
        return 1
      fi
      team="$target_team"
      target="$target_agent"
    fi
    shutdown_args+=("--agent" "$target")
  done

  [[ -n "$team" ]] || { echo "error: -t <team> is required for teammateShutdown." >&2; return 1; }
  (( ${#shutdown_args[@]} > 0 )) || { echo "error: provide at least one teammate agent." >&2; return 1; }

  shutdown_args=(-t "$team" "${shutdown_args[@]}")
  [[ -n "$timeout" ]] && shutdown_args+=("--timeout" "$timeout")
  [[ -n "$reason" ]] && shutdown_args+=("--reason" "$reason")
  _xmux_cmd_shutdown "${shutdown_args[@]}"
}

_xmux_cmd_team_shutdown() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--agent" ]]; then
      echo "error: teamShutdown does not accept --agent. Use xmux teammateShutdown -t <team> <agent>." >&2
      return 1
    fi
  done
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: xmux teamShutdown -t <team> [--timeout <seconds>] [--no-archive] [--reason <reason>]"
    return 0
  fi
  _xmux_cmd_shutdown "$@"
}

xmux() {
  _xmux_refresh_home
  local cmd="${1:-}"

  case "$cmd" in
    ""|-*)
      _xmux_start "$@"
      ;;
    start)
      shift
      _xmux_start "$@"
      ;;
    teamCreate|team-create)
      shift
      _xmux_cmd_team_create "$@"
      ;;
    teammateAdd|teammate-add)
      shift
      _xmux_cmd_teammate_add "$@"
      ;;
    teamStatus|team-status)
      shift
      _xmux_cmd_team_status "$@"
      ;;
    teammateStatus|teammate-status)
      shift
      _xmux_cmd_teammate_status "$@"
      ;;
    teammateShutdown|teammate-shutdown)
      shift
      _xmux_cmd_teammate_shutdown "$@"
      ;;
    teamShutdown|team-shutdown)
      shift
      _xmux_cmd_team_shutdown "$@"
      ;;
    claude)
      shift
      xmux-claude "$@"
      ;;
    gemini)
      shift
      xmux-gemini "$@"
      ;;
    copilot)
      shift
      xmux-copilot "$@"
      ;;
    codex|codex-"worker"|xmux-codex)
      echo "error: Codex teammates are unsupported in XMux; Codex is the lead only. Use xmux claude, xmux gemini, or xmux copilot." >&2
      return 1
      ;;
    teammates|team)
      shift
      _xmux_cmd_teammates "$@"
      ;;
    sessions)
      shift
      _xmux_cmd_sessions "$@"
      ;;
    pane-info|pane)
      shift
      _xmux_cmd_pane_info "$@"
      ;;
    doctor)
      shift
      _xmux_cmd_doctor "$@"
      ;;
    setup-codex|setupCodex)
      shift
      _xmux_cmd_setup_codex "$@"
      ;;
    doctor-codex|doctorCodex)
      shift
      _xmux_cmd_doctor_codex "$@"
      ;;
    remove-codex|removeCodex)
      shift
      _xmux_cmd_remove_codex "$@"
      ;;
    bridge-status|bridge)
      shift
      _xmux_cmd_bridge_status "$@"
      ;;
    ensure)
      shift
      _xmux_cmd_ensure "$@"
      ;;
    recover)
      shift
      _xmux_cmd_recover "$@"
      ;;
    submit-test)
      shift
      _xmux_cmd_submit_test "$@"
      ;;
    send)
      shift
      _xmux_cmd_send "$@"
      ;;
    attach|focus)
      shift
      _xmux_cmd_attach "$@"
      ;;
    shutdown)
      shift
      _xmux_cmd_shutdown "$@"
      ;;
    status)
      shift
      _xmux_cmd_teammates "$@"
      ;;
    help|-h|--help)
      _xmux_usage
      ;;
    *)
      echo "error: unknown xmux command '$cmd'." >&2
      _xmux_usage
      return 1
      ;;
  esac
}
