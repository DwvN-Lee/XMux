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

_xmux_runtime_env_assignments() {
  print -r -- "XMUX_INSTALL_DIR=$(_xmux_q "$XMUX_INSTALL_DIR") XMUX_PROJECT_DIR=$(_xmux_q "$XMUX_PROJECT_DIR") XMUX_STATE_DIR=$(_xmux_q "$XMUX_STATE_DIR")"
}

_xmux_codex_home_env_name() {
  print -r -- "CODEX_"HOME
}

_xmux_usage() {
  cat >&2 <<'EOF'
Usage:
  xmux [start] [-n <session_name>] [-T <team>] [--claude] [--gemini] [--copilot] [--] [codex args...]
  xmux claude|gemini|copilot -t <team> [-n <agent_name>] [-x <timeout_sec>] [--] [provider args...]
  xmux teammates [-t <team>]
  xmux sessions [--filter <pattern>] [--all]
  xmux pane-info [<target>] [-t <team>] [-n <lines>]
  xmux doctor [-t <team>] [--log-lines <n>]
  xmux bridge-status [-t <team>] [<agent>] [--log-lines <n>]
  xmux recover -t <team> <agent> --restart-bridge|--restart-teammate [--session <session>]
  xmux submit-test -t <team> <agent> [--text <text>] [--delay <seconds>] [--force]
  xmux send <target> "<text>" [--clear] [--no-enter] [--force]
  xmux attach [<target>] [-t <team>]
  xmux stop [-t <team>] <agent|pane>

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
  local cfg
  for cfg in "$XMUX_STATE_DIR"/teams/*/team.json(N); do
    print -r -- "${cfg:h:t}"
  done
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
  command -v tmux &>/dev/null && have_tmux=1

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
print(f"mailbox: status={payload.get('status', 'unknown')} team_dir={payload.get('team_dir', '-')}")
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
  command -v tmux &>/dev/null && have_tmux=1

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
  local team_dir pid_file port log_file

  team_dir="$(_xmux_team_dir "$team")"
  pid_file="$team_dir/.${agent}-mcp-http.pid"
  log_file="/tmp/xmux-mcp-http-${team}-${agent}.log"

  mkdir -p "$team_dir/inboxes"
  [[ -f "$outbox" ]] || print -r -- '[]' > "$outbox"

  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid=$(< "$pid_file")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
    fi
  fi

  port="$(_xmux_free_port)" || return 1
  local env_prefix mcp_cmd wait_cmd
  env_prefix="$(_xmux_runtime_env_assignments)"
  wait_cmd="$(_xmux_tmux_wait_expected_sigterm)"
  mcp_cmd="env -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_OUTBOX=$(_xmux_q "$outbox") XMUX_AGENT=$(_xmux_q "$agent") XMUX_TEAM=$(_xmux_q "$team") node $(_xmux_q "$XMUX_INSTALL_DIR/bridge-mcp-server.js") --http $(_xmux_q "$port") >> $(_xmux_q "$log_file") 2>&1 & printf '%s\n' \"\$!\" > $(_xmux_q "$pid_file"); $wait_cmd"
  tmux run-shell -b "$mcp_cmd" || return 1

  local tries=0
  until curl -sf "http://127.0.0.1:${port}/sse" -o /dev/null --max-time 0.2 2>/dev/null \
      || (( tries++ >= 10 )); do
    sleep 0.2
  done

  if [[ -f "$XMUX_INSTALL_DIR/scripts/setup_copilot_mcp.py" ]]; then
    python3 "$XMUX_INSTALL_DIR/scripts/setup_copilot_mcp.py" "http://127.0.0.1:${port}/sse" >/dev/null
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

  local bridge_cmd env_prefix pid_file wait_cmd
  pid_file="$team_dir/.${agent}-bridge.pid"
  env_prefix="$(_xmux_runtime_env_assignments)"
  wait_cmd="$(_xmux_tmux_wait_expected_sigterm)"
  bridge_cmd="env -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_LEAD_AGENT=$(_xmux_q "$XMUX_LEAD_AGENT") zsh $(_xmux_q "$XMUX_INSTALL_DIR/xmux-bridge.zsh") -p $(_xmux_q "$pane") -T $(_xmux_q "$team") -a $(_xmux_q "$agent") -P $(_xmux_q "$provider") -i $(_xmux_q "$inbox") -x $(_xmux_q "$timeout") -w $(_xmux_q "$idle_pattern") -d $(_xmux_q "$submit_delay") >> $(_xmux_q "$bridge_log") 2>&1 & printf '%s\n' \"\$!\" > $(_xmux_q "$pid_file"); $wait_cmd"
  tmux run-shell -b "$bridge_cmd" || return 1
}

_xmux_cmd_stop() {
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
        echo "Usage: xmux stop [-t <team>] <agent|pane>"
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
  [[ -n "$target" ]] || { echo "error: target is required." >&2; return 1; }

  local pane agent team_name is_lead pid_file session current_pane lead_pane restore_pane
  pane="$(_xmux_resolve_target_to_pane "$target" "$team")" || return $?
  is_lead=$(tmux display-message -t "$pane" -p '#{@xmux-lead}' 2>/dev/null)
  if [[ "$is_lead" == "1" ]]; then
    echo "error: refusing to stop the Codex lead pane via xmux stop." >&2
    return 1
  fi

  agent=$(tmux display-message -t "$pane" -p '#{@xmux-agent}' 2>/dev/null)
  team_name=$(tmux display-message -t "$pane" -p '#{@xmux-team}' 2>/dev/null)
  [[ -z "$agent" && "$target" != %* ]] && agent="$target"
  [[ -z "$team_name" ]] && team_name="$team"
  if [[ -z "$agent" || -z "$team_name" ]]; then
    echo "error: refusing to stop a pane that is not tagged as an XMux teammate." >&2
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

  pid_file="$(_xmux_team_dir "$team_name")/.${agent}-bridge.pid"
  _xmux_kill_pid_file "$pid_file" "$team_name:$agent bridge"

  local http_pid_file
  http_pid_file="$(_xmux_team_dir "$team_name")/.${agent}-mcp-http.pid"
  _xmux_kill_pid_file "$http_pid_file" "$team_name:$agent http mcp"

  tmux kill-pane -t "$pane" || return 1
  _xmux_mark_member_inactive "$team_name" "$agent" || true
  _xmux_select_pane_if_alive "$restore_pane" || _xmux_select_pane_if_alive "$lead_pane" || true
  echo "[xmux] stopped ${agent:-$pane} pane:$pane team:${team_name:-unknown}"
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

  local team_dir pane timeout idle_pattern submit_delay env_file
  team_dir="$(_xmux_team_dir "$team")"
  env_file="$team_dir/.bridge-${target}.env"
  pane="$(_xmux_member_field "$team" "$target" pane 2>/dev/null)"
  timeout=60
  idle_pattern="$(_xmux_bridge_env_value "$env_file" XMUX_IDLE_PATTERN 2>/dev/null)"
  [[ -z "$idle_pattern" ]] && idle_pattern="$(_xmux_provider_idle_pattern "$provider")"
  submit_delay="$(_xmux_bridge_env_value "$env_file" XMUX_SUBMIT_DELAY 2>/dev/null)"
  [[ -z "$submit_delay" ]] && submit_delay="$(_xmux_provider_submit_delay "$provider")"

  if [[ "$action" == "restart-bridge" ]]; then
    if [[ -z "$pane" || "$pane" == "-" ]] || ! _xmux_pane_exists "$pane"; then
      echo "error: cannot restart bridge because $team:$target has no live pane." >&2
      return 1
    fi
    _xmux_kill_pid_file "$team_dir/.${target}-bridge.pid" "$team:$target bridge"
    _xmux_start_member_bridge "$team" "$target" "$provider" "$pane" "$timeout" "$idle_pattern" "$submit_delay" || return 1
    echo "[xmux] restarted bridge for $team:$target pane:$pane"
    return 0
  fi

  [[ -n "$session" ]] || session="$(_xmux_session_for_team "$team")"
  [[ -n "$session" ]] || { echo "error: cannot determine tmux session for team '$team'; pass --session." >&2; return 1; }
  _xmux_validate_session_name "$session" || return 1

  if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
    _xmux_cmd_stop -t "$team" "$target" || return 1
  else
    _xmux_kill_pid_file "$team_dir/.${target}-bridge.pid" "$team:$target bridge"
    _xmux_kill_pid_file "$team_dir/.${target}-mcp-http.pid" "$team:$target http mcp"
    _xmux_mark_member_inactive "$team" "$target" || true
  fi

  case "$provider" in
    claude) xmux-claude -t "$team" -n "$target" -s "$session" ;;
    gemini) xmux-gemini -t "$team" -n "$target" -s "$session" ;;
    copilot) xmux-copilot -t "$team" -n "$target" -s "$session" ;;
  esac
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
  if [[ -f "$XMUX_INSTALL_DIR/scripts/trust_codex_project.py" ]]; then
    python3 "$XMUX_INSTALL_DIR/scripts/trust_codex_project.py" "$XMUX_PROJECT_DIR" >/dev/null 2>&1 || true
  fi

  if [[ -f "$XMUX_INSTALL_DIR/scripts/setup_xmux_codex_mcp.py" ]]; then
    python3 "$XMUX_INSTALL_DIR/scripts/setup_xmux_codex_mcp.py" \
      --xmux-install-dir "$XMUX_INSTALL_DIR" \
      --xmux-project-dir "$XMUX_PROJECT_DIR" \
      --xmux-state-dir "$XMUX_STATE_DIR" \
      --server-path "$XMUX_INSTALL_DIR/xmux-lead-mcp-server.js" >/dev/null 2>&1 || {
        echo "[xmux] warning: failed to configure XMux Codex MCP in ~/.codex/config.toml." >&2
      }
  fi
}

_xmux_build_codex_env_command() {
  local team_name="$1" team_dir="$2"
  shift 2
  [[ "${1:-}" == "--" ]] && shift
  local codex_cmd arg codex_home_env env_prefix
  codex_home_env="$(_xmux_codex_home_env_name)"
  env_prefix="$(_xmux_runtime_env_assignments)"
  codex_cmd="exec env -u $(_xmux_q "$codex_home_env") -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_TEAM=$(_xmux_q "$team_name") XMUX_AGENT=$(_xmux_q "$XMUX_LEAD_AGENT") XMUX_TEAM_DIR=$(_xmux_q "$team_dir") codex"
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

  if [[ -n "$TMUX" ]]; then
    local session lead_pane
    session=$(tmux display-message -p '#S' 2>/dev/null)
    _xmux_validate_session_name "$session" || return 1
    lead_pane="$TMUX_PANE"
    _xmux_mailbox_init_team "$team_name" "$lead_pane" "$session"

    (( spawn_claude )) && xmux-claude -t "$team_name"
    (( spawn_gemini )) && xmux-gemini -t "$team_name"
    (( spawn_copilot )) && xmux-copilot -t "$team_name"

    local codex_home_env
    codex_home_env="$(_xmux_codex_home_env_name)"
    env -u "$codex_home_env" -u XMUX_DIR -u XMUX_HOME \
      XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
      XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
      XMUX_STATE_DIR="$XMUX_STATE_DIR" \
      XMUX_TEAM="$team_name" \
      XMUX_AGENT="$XMUX_LEAD_AGENT" \
      XMUX_TEAM_DIR="$team_dir" \
      codex "${codex_args[@]}"
    return
  fi

  codex_cmd="$(_xmux_build_codex_env_command "$team_name" "$team_dir" -- "${codex_args[@]}")"

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

  tmux attach-session -t "$session_name"
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
    bridge-status|bridge)
      shift
      _xmux_cmd_bridge_status "$@"
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
    stop)
      shift
      _xmux_cmd_stop "$@"
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
