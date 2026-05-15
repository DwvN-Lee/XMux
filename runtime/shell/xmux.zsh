# runtime/shell/xmux.zsh - Codex-led XMux shell layer.
#
# Source this file from zsh, then run:
#   xmux [-n <session>] [codex args...]

if [[ -n "$ZSH_VERSION" ]]; then
  _XMUX_SOURCED_DIR="${${(%):-%x}:A:h}"
else
  _XMUX_SOURCED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi
_XMUX_SOURCE_INSTALL_DIR="$_XMUX_SOURCED_DIR"
if [[ "${_XMUX_SOURCE_INSTALL_DIR:t}" == "shell" && "${_XMUX_SOURCE_INSTALL_DIR:h:t}" == "runtime" ]]; then
  _XMUX_SOURCE_INSTALL_DIR="${_XMUX_SOURCE_INSTALL_DIR:h:h}"
fi

if [[ -n "${XMUX_INSTALL_DIR+x}" && -n "${XMUX_INSTALL_DIR}" ]]; then
  XMUX_INSTALL_DIR="${XMUX_INSTALL_DIR:A}"
else
  XMUX_INSTALL_DIR="$_XMUX_SOURCE_INSTALL_DIR"
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

XMUX_VERSION="1.3.0"
XMUX_LEAD_AGENT="${XMUX_LEAD_AGENT:-codex-lead}"

_xmux_q() {
  printf '%q' "$1"
}

_xmux_homebrew_opt_install_dir() {
  local install_dir="${1:A}"
  case "$install_dir" in
    */Cellar/xmux/*/libexec)
      local prefix="${install_dir%%/Cellar/xmux/*/libexec}"
      local candidate="$prefix/opt/xmux/libexec"
      if [[ -f "$candidate/runtime/shell/xmux.zsh" || -f "$candidate/xmux.zsh" ]]; then
        print -r -- "$candidate"
        return 0
      fi
      ;;
  esac
  return 1
}

_xmux_mcp_install_dir() {
  _xmux_homebrew_opt_install_dir "$XMUX_INSTALL_DIR" || print -r -- "$XMUX_INSTALL_DIR"
}

_xmux_package_spec_has_version() {
  local spec="$1"
  if [[ "$spec" == @* ]]; then
    [[ "${spec#@}" == *@* ]]
  else
    [[ "$spec" == *@* ]]
  fi
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

_xmux_mcp_package_spec() {
  local package_spec="${XMUX_MCP_PACKAGE_SPEC:-${XMUX_MCP_NPM_PACKAGE:-xmux}}"
  if _xmux_package_spec_has_version "$package_spec"; then
    print -r -- "$package_spec"
  else
    print -r -- "${package_spec}@${XMUX_VERSION}"
  fi
}

_xmux_mcp_npx_prefix() {
  print -r -- "${XMUX_MCP_NPX_PREFIX:-$HOME/.cache/xmux/npm-prefix}"
}

_xmux_mcp_cached_package_root() {
  local package_spec package_name
  package_spec="$(_xmux_mcp_package_spec)"
  package_name="$(_xmux_package_name_from_spec "$package_spec")"
  print -r -- "$(_xmux_mcp_npx_prefix)/node_modules/$package_name"
}

_xmux_mcp_bridge_path() {
  return 1
}

_xmux_mcp_lead_path() {
  return 1
}

_xmux_mcp_bridge_ref() {
  return 1
}

_xmux_mcp_bridge_identity() {
  print -r -- "disabled"
}

_xmux_mailbox_cli_path() {
  local candidate
  for candidate in \
      "${XMUX_MAILBOX_NODE_CLI:-}" \
      "$(_xmux_mcp_install_dir)/dist/bin/xmux-mailbox.js"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  return 1
}

_xmux_mailbox_bin_path() {
  return 1
}

_xmux_mailbox_source() {
  local bin_path script_path
  if bin_path="$(_xmux_mailbox_bin_path 2>/dev/null)"; then
    print -r -- "npm-cache:$bin_path"
  elif script_path="$(_xmux_mailbox_cli_path 2>/dev/null)"; then
    case "$script_path" in
      "$(_xmux_mcp_install_dir)"/dist/bin/xmux-mailbox.js) print -r -- "brew-bundled:$script_path" ;;
      *) print -r -- "npm-cache:$script_path" ;;
    esac
  else
    return 1
  fi
}

_xmux_mailbox_cli() {
  local bin_path script_path
  if bin_path="$(_xmux_mailbox_bin_path 2>/dev/null)"; then
    command "$bin_path" "$@"
    return
  fi
  if script_path="$(_xmux_mailbox_cli_path 2>/dev/null)"; then
    node "$script_path" "$@"
    return
  fi
  return 127
}

_xmux_claude_harness_cli_path() {
  local candidate
  for candidate in \
      "$XMUX_INSTALL_DIR/dist/bin/xmux-claude-harness.js" \
      "$XMUX_INSTALL_DIR/src/claude/cli.js" \
      "$(_xmux_mcp_install_dir)/dist/bin/xmux-claude-harness.js"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  return 1
}

_xmux_claude_harness_cli() {
  local script_path
  if script_path="$(_xmux_claude_harness_cli_path 2>/dev/null)"; then
    node "$script_path" "$@"
    return
  fi
  if [[ -f "$XMUX_INSTALL_DIR/src/claude/cli.js" ]]; then
    node "$XMUX_INSTALL_DIR/src/claude/cli.js" "$@"
    return
  fi
  return 127
}

_xmux_cmd_claude_harness() {
  XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    _xmux_claude_harness_cli "$@"
}

_xmux_codex_harness_cli_path() {
  local candidate
  for candidate in \
      "$XMUX_INSTALL_DIR/dist/bin/xmux-codex-harness.js" \
      "$XMUX_INSTALL_DIR/src/codex/cli.js" \
      "$(_xmux_mcp_install_dir)/dist/bin/xmux-codex-harness.js"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  return 1
}

_xmux_codex_harness_cli() {
  local script_path
  if script_path="$(_xmux_codex_harness_cli_path 2>/dev/null)"; then
    node "$script_path" "$@"
    return
  fi
  if [[ -f "$XMUX_INSTALL_DIR/src/codex/cli.js" ]]; then
    node "$XMUX_INSTALL_DIR/src/codex/cli.js" "$@"
    return
  fi
  return 127
}

_xmux_cmd_codex_harness() {
  XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    _xmux_codex_harness_cli "$@"
}

_xmux_provider_brand_color() {
  local provider="$1"
  case "$provider" in
    codex) print -r -- "#10A37F" ;;
    claude) print -r -- "#D97757" ;;
    gemini) print -r -- "#4285F4" ;;
    copilot) print -r -- "#8534F3" ;;
    *) print -r -- "#10A37F" ;;
  esac
}

_xmux_status_style_enabled() {
  local value="${XMUX_STATUS_STYLE:-1}"
  case "$value" in
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) return 0 ;;
  esac
}

_xmux_status_brand_color() {
  local token="$1"
  case "$token" in
    accent) _xmux_provider_brand_color codex ;;
    bg) print -r -- "#0E0F12" ;;
    surface) print -r -- "#15171C" ;;
    chip1_bg) print -r -- "#17191D" ;;
    chip1_fg) print -r -- "#F3F4F6" ;;
    chip2_bg) print -r -- "#252A31" ;;
    chip2_fg) print -r -- "#F5F7FA" ;;
    display_bg) print -r -- "#252A31" ;;
    display_fg) print -r -- "#F5F7FA" ;;
    fg) print -r -- "#F5F7FA" ;;
    muted) print -r -- "#9EA1AA" ;;
    *) print -r -- "#F5F7FA" ;;
  esac
}

_xmux_terminal_theme_can_emit() {
  [[ -t 1 || "${XMUX_TERMINAL_THEME_FORCE:-0}" == "1" ]]
}

_xmux_terminal_theme_enabled() {
  local value="${XMUX_TERMINAL_THEME:-1}"
  case "$value" in
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) _xmux_terminal_theme_can_emit ;;
  esac
}

_xmux_terminal_osc() {
  _xmux_terminal_theme_can_emit || return 0
  printf '\033]%s\033\\' "$1"
}

_xmux_apply_terminal_codex_theme() {
  _xmux_terminal_osc "10;#F5F7FA"
  _xmux_terminal_osc "11;#0E0F12"
  _xmux_terminal_osc "12;#10A37F"

  _xmux_terminal_osc "4;0;#0E0F12"
  _xmux_terminal_osc "4;1;#FF6B6B"
  _xmux_terminal_osc "4;2;#10A37F"
  _xmux_terminal_osc "4;3;#F2C94C"
  _xmux_terminal_osc "4;4;#4285F4"
  _xmux_terminal_osc "4;5;#8534F3"
  _xmux_terminal_osc "4;6;#2DD4BF"
  _xmux_terminal_osc "4;7;#F5F7FA"
  _xmux_terminal_osc "4;8;#9EA1AA"
  _xmux_terminal_osc "4;9;#FF8A80"
  _xmux_terminal_osc "4;10;#36D399"
  _xmux_terminal_osc "4;11;#FFD166"
  _xmux_terminal_osc "4;12;#6EA8FE"
  _xmux_terminal_osc "4;13;#A371F7"
  _xmux_terminal_osc "4;14;#5EEAD4"
  _xmux_terminal_osc "4;15;#FFFFFF"
  _xmux_terminal_osc "4;256;#F5F7FA"
}

_xmux_reset_terminal_theme() {
  _xmux_terminal_osc "110"
  _xmux_terminal_osc "111"
  _xmux_terminal_osc "112"
  _xmux_terminal_osc "104"
  _xmux_terminal_osc "105"
}

_xmux_with_terminal_codex_theme() {
  local rc=0 applied=0
  if _xmux_terminal_theme_enabled; then
    _xmux_apply_terminal_codex_theme
    applied=1
  fi
  {
    "$@"
    rc=$?
  } always {
    (( applied )) && _xmux_reset_terminal_theme
  }
  return "$rc"
}

_xmux_attach_session() {
  local session="$1"
  _xmux_with_terminal_codex_theme tmux attach-session -t "$session"
}

_xmux_status_literal_label() {
  local label="$1"
  label="${label//[[:cntrl:]]/ }"
  label="${label//\#/##}"
  print -r -- "$label"
}

_xmux_apply_session_brand_status() {
  local session="$1" team="$2" display_name="${3:-$2}"
  local display_label=""
  _xmux_status_style_enabled || return 0
  [[ -n "$session" && -n "$team" ]] || return 0

  local accent bg surface chip1_bg chip1_fg chip2_bg chip2_fg display_bg display_fg fg muted
  accent="$(_xmux_status_brand_color accent)"
  bg="$(_xmux_status_brand_color bg)"
  surface="$(_xmux_status_brand_color surface)"
  chip1_bg="$(_xmux_status_brand_color chip1_bg)"
  chip1_fg="$(_xmux_status_brand_color chip1_fg)"
  chip2_bg="$(_xmux_status_brand_color chip2_bg)"
  chip2_fg="$(_xmux_status_brand_color chip2_fg)"
  display_bg="$(_xmux_status_brand_color display_bg)"
  display_fg="$(_xmux_status_brand_color display_fg)"
  fg="$(_xmux_status_brand_color fg)"
  muted="$(_xmux_status_brand_color muted)"
  display_label="$(_xmux_status_literal_label "$display_name")"

  tmux set-option -t "$session" status on 2>/dev/null
  tmux set-option -t "$session" status-position bottom 2>/dev/null
  tmux set-option -t "$session" status-style "bg=${bg},fg=${fg}" 2>/dev/null
  tmux set-option -t "$session" status-left-length 120 2>/dev/null
  tmux set-option -t "$session" status-right-length 45 2>/dev/null
  tmux set-option -t "$session" status-left "#[bg=${accent},fg=${bg},bold] XMux #[bg=${display_bg},fg=${display_fg},nobold] ${display_label} #[bg=${chip1_bg},fg=${chip1_fg}] #W " 2>/dev/null
  tmux set-option -t "$session" status-right "#[bg=${chip1_bg},fg=${chip1_fg}] xmux ${XMUX_VERSION} #[bg=${chip2_bg},fg=${chip2_fg}] %H:%M " 2>/dev/null
  tmux set-option -t "$session" window-status-format "" 2>/dev/null
  tmux set-option -t "$session" window-status-current-format "" 2>/dev/null
  tmux set-option -t "$session" window-status-separator "" 2>/dev/null
  tmux set-option -t "$session" message-style "bg=${accent},fg=${bg}" 2>/dev/null
  tmux set-window-option -t "$session" mode-style "bg=${accent},fg=${bg}" 2>/dev/null
  return 0
}

_xmux_apply_pane_brand_style() {
  local pane="$1" agent="$2" provider="$3"
  local name_color border_color
  name_color="$(_xmux_provider_brand_color "$provider")"
  border_color="$(_xmux_provider_brand_color codex)"

  tmux select-pane -t "$pane" -T "$agent" 2>/dev/null
  tmux set-option -p -t "$pane" @agent_name "$agent" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-provider "$provider" 2>/dev/null
  tmux set-option -p -t "$pane" pane-border-style "fg=${border_color}" 2>/dev/null
  tmux set-option -p -t "$pane" pane-active-border-style "fg=${border_color},bold" 2>/dev/null
  tmux set-option -p -t "$pane" pane-border-format "#[fg=${name_color},bold] #{@agent_name} #[default]" 2>/dev/null
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

_xmux_user_usage() {
  cat >&2 <<'EOF'
Usage:
  xmux [-n <session_name>] [-T <team>] [--shutdown-on-lead-exit|--keep-team-on-lead-exit] [--] [codex args...]
  xmux start [-n <session_name>] [-T <team>] [--shutdown-on-lead-exit|--keep-team-on-lead-exit] [--] [codex args...]
  xmux setup-codex
  xmux doctor-codex
  xmux remove-codex
  xmux install-skills
  xmux remove-skills
  xmux codex sessions|ensure-hooks|status|send|hook
  xmux claude sessions|start|ensure-hooks|send|read|status|stop
  xmux theme-reset
  xmux --version

  xmux help debug
  xmux help all

Starts Codex as the XMux lead through the Codex pane harness. Claude harness
commands are exposed through the single `xmux claude ...` entrypoint. Legacy
teammate lifecycle and pane injection commands are disabled.
EOF
}

_xmux_agent_usage() {
  cat >&2 <<'EOF'
Agent commands:
  xmux teamCreate -t <team> [-n <session_name>] [claude|gemini|copilot ...] [--shutdown-on-lead-exit|--keep-team-on-lead-exit] [--] [codex args...]
  xmux teammateAdd -t <team> [--session <session_name>] <claude|gemini|copilot>...
  xmux teamStatus [-t <team>]
  xmux teammateStatus -t <team> [<agent>]
  xmux teammateShutdown -t <team> <agent>... [--timeout <seconds>] [--reason <reason>]
  xmux teamShutdown -t <team> [--timeout <seconds>] [--no-archive] [--reason <reason>]

These commands are kept for Codex-led automation and are intentionally hidden
from the default user help.
EOF
}

_xmux_debug_usage() {
  cat >&2 <<'EOF'
Debug commands:
  xmux sessions [--filter <pattern>] [--all]
  xmux paneInfo [<target>] [-t <team>] [-n <lines>]
  xmux doctor [-t <team>] [--log-lines <n>]
  xmux attach [<target>] [-t <team>]

Use `xmux claude ...` for Claude harness state and communication checks. Legacy
teammate communication, MCP bridge checks, and pane prompt injection are disabled.
EOF
}

_xmux_legacy_teammate_disabled() {
  local command_name="${1:-this command}"
  echo "error: $command_name is disabled in the Claude hook harness. Use 'xmux claude ...'." >&2
  return 1
}

_xmux_usage() {
  _xmux_user_usage
}

_xmux_print_version() {
  print -r -- "xmux $XMUX_VERSION"
}

_xmux_help() {
  local topic="${1:-user}"
  case "$topic" in
    ""|user)
      _xmux_user_usage
      ;;
    debug)
      _xmux_debug_usage
      ;;
    all)
      _xmux_user_usage
      echo >&2
      _xmux_debug_usage
      ;;
    -h|--help)
      cat >&2 <<'EOF'
Usage: xmux help [user|debug|all]
EOF
      ;;
    *)
      echo "error: unknown help topic '$topic'." >&2
      echo "Usage: xmux help [user|debug|all]" >&2
      return 1
      ;;
  esac
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

_xmux_active_team_registry_root() {
  if [[ -n "${XMUX_ACTIVE_TEAM_REGISTRY_DIR:-}" ]]; then
    print -r -- "${XMUX_ACTIVE_TEAM_REGISTRY_DIR:A}"
    return
  fi
  print -r -- "${HOME:-$PWD}/.codex/xmux/active-teams"
}

_xmux_active_team_registry_file() {
  print -r -- "$(_xmux_active_team_registry_root)/$1.json"
}

_xmux_record_active_team_registry() {
  local team="$1" pane="$2" session="$3" display_name="${4:-$1}"
  local file team_dir
  file="$(_xmux_active_team_registry_file "$team")"
  team_dir="$(_xmux_team_dir "$team")"
  node - "$file" "$team" "$XMUX_PROJECT_DIR" "$XMUX_STATE_DIR" "$team_dir" "$session" "$pane" "$display_name" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , filePath, team, projectDir, stateDir, teamDir, session, pane, displayName] = process.argv;
const payload = {
  schema: 'xmux.active_team.v1',
  team,
  project_dir: path.resolve(projectDir),
  state_dir: path.resolve(stateDir),
  team_dir: path.resolve(teamDir),
  session,
  lead_pane: pane,
  display_name: displayName,
  status: 'active',
  updated_at: new Date().toISOString(),
};
fs.mkdirSync(path.dirname(filePath), { recursive: true });
const tmp = `${filePath}.tmp.${process.pid}`;
fs.writeFileSync(tmp, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, filePath);
JS
}

_xmux_remove_active_team_registry() {
  local team="$1" file
  file="$(_xmux_active_team_registry_file "$team")"
  node - "$file" "$team" "$XMUX_STATE_DIR" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , filePath, team, stateDir] = process.argv;
let payload;
try {
  payload = JSON.parse(fs.readFileSync(filePath, 'utf8'));
} catch (_) {
  process.exit(0);
}
if (!payload || typeof payload !== 'object' || payload.team !== team) {
  process.exit(0);
}
const expectedState = stateDir ? path.resolve(stateDir) : '';
const actualState = payload.state_dir ? path.resolve(String(payload.state_dir)) : '';
if (expectedState && actualState && expectedState !== actualState) {
  process.exit(0);
}
try {
  fs.unlinkSync(filePath);
} catch (_) {}
JS
}

_xmux_refresh_active_team_registry() {
  local team="$1" cfg pane session display_name
  cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1
  pane="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" pane 2>/dev/null || true)"
  session="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" session 2>/dev/null || true)"
  display_name="$(node - "$cfg" "$team" <<'JS'
const fs = require('fs');
const [, , cfgPath, fallback] = process.argv;
try {
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  process.stdout.write(String(cfg.display_name || fallback));
} catch (_) {
  process.stdout.write(fallback);
}
JS
)"
  _xmux_record_active_team_registry "$team" "$pane" "$session" "$display_name"
}

_xmux_slug_component() {
  local raw="$1" fallback="${2:-item}"
  local slug="${raw//[^A-Za-z0-9_-]/_}"
  [[ -z "$slug" ]] && slug="$fallback"
  print -r -- "$slug"
}

_xmux_short_hash() {
  local value="$1"
  if command -v md5sum &>/dev/null; then
    printf '%s' "$value" | md5sum | head -c 6
  elif command -v md5 &>/dev/null; then
    printf '%s' "$value" | md5 | head -c 6
  else
    printf '%s' "$value" | cksum | awk '{print substr($1,1,6)}'
  fi
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

_xmux_project_display_name() {
  _xmux_slug_component "${XMUX_PROJECT_DIR:t}" project
}

_xmux_resolve_name_fields() {
  local raw_name="$1"
  local project raw_short display_short display_name base hash team session

  project="$(_xmux_project_display_name)"
  raw_short="${raw_name:-$(_xmux_default_session_name)}"
  raw_short="${raw_short#${project}/}"
  raw_short="${raw_short#${project}:}"
  raw_short="${raw_short#${project}-}"
  [[ -z "$raw_short" ]] && raw_short="default"
  display_short="$(_xmux_slug_component "$raw_short" default)"
  display_name="${project}/${display_short}"
  base="$(_xmux_slug_component "${project}-${display_short}" xmux)"
  hash="$(_xmux_short_hash "${XMUX_PROJECT_DIR}:${raw_short}")"
  team="${base}-${hash}"
  session="xmux-${base}-${hash}"

  print -r -- "$display_name"$'\t'"$team"$'\t'"$session"
}

_xmux_session_attached_count() {
  local session="$1" current_session attached_count
  while IFS=$'\t' read -r current_session attached_count; do
    [[ "$current_session" == "$session" ]] || continue
    print -r -- "$attached_count"
    return 0
  done < <(tmux list-sessions -F $'#{session_name}\t#{session_attached}' 2>/dev/null)
  print -r -- ""
}

_xmux_session_owned_by_team() {
  local session="$1" team="$2"
  [[ "$(tmux show-option -v -t "$session" @xmux-team 2>/dev/null)" == "$team" ]]
}

_xmux_error_name_active() {
  local display_name="$1"
  echo "error: XMux name '$display_name' is already active." >&2
  echo "       Use 'xmux attach $display_name' to reconnect, or 'xmux sessions' to inspect active runtimes." >&2
}

_xmux_error_name_attached() {
  local display_name="$1"
  echo "error: XMux name '$display_name' is already attached by another terminal." >&2
  echo "       Multiple terminals cannot attach to the same XMux name." >&2
}

_xmux_error_unowned_internal_session() {
  local display_name="$1"
  echo "error: internal tmux session for XMux name '$display_name' already exists but is not owned by this XMux runtime." >&2
  echo "       Inspect raw tmux sessions with 'tmux ls' and choose another XMux name." >&2
}

_xmux_error_name_owned_by_team() {
  local display_name="$1" team="$2"
  echo "error: XMux name '$display_name' is already active for team '$team'." >&2
  echo "       Use 'xmux attach $display_name' or choose a different -n name." >&2
}

_xmux_error_name_ambiguous() {
  local display_name="$1" teams="$2"
  echo "error: XMux name '$display_name' matches multiple active teams: $teams" >&2
  echo "       Use 'xmux attach -t <team>' to disambiguate." >&2
}

_xmux_guard_scoped_name_available() {
  local scoped_name_requested="$1" display_name="$2" team_name="$3" session_name="$4"
  local existing_display_team="" display_lookup_rc=0
  local attached_count owner_session

  (( scoped_name_requested == 1 )) || return 0

  if existing_display_team="$(_xmux_team_for_display_name "$display_name")"; then
    display_lookup_rc=0
  else
    display_lookup_rc=$?
  fi
  if (( display_lookup_rc == 2 )); then
    return 1
  fi
  if (( display_lookup_rc == 0 )) && [[ -n "$existing_display_team" ]]; then
    if [[ "$existing_display_team" != "$team_name" ]]; then
      _xmux_error_name_owned_by_team "$display_name" "$existing_display_team"
      return 1
    fi

    if tmux has-session -t "$session_name" 2>/dev/null; then
      if ! _xmux_session_owned_by_team "$session_name" "$team_name"; then
        _xmux_error_unowned_internal_session "$display_name"
        return 1
      fi
      attached_count="$(_xmux_session_attached_count "$session_name")"
      if [[ -n "$attached_count" && "$attached_count" != "0" ]]; then
        _xmux_error_name_attached "$display_name"
        return 1
      fi
      _xmux_error_name_active "$display_name"
      return 1
    fi

    owner_session="$(_xmux_member_field "$team_name" "$XMUX_LEAD_AGENT" session 2>/dev/null || true)"
    if [[ -n "$owner_session" && "$owner_session" != "-" ]] && tmux has-session -t "$owner_session" 2>/dev/null; then
      attached_count="$(_xmux_session_attached_count "$owner_session")"
      if [[ -n "$attached_count" && "$attached_count" != "0" ]]; then
        _xmux_error_name_attached "$display_name"
        return 1
      fi
    fi
    _xmux_error_name_active "$display_name"
    return 1
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    if ! _xmux_session_owned_by_team "$session_name" "$team_name"; then
      _xmux_error_unowned_internal_session "$display_name"
      return 1
    fi
    attached_count="$(_xmux_session_attached_count "$session_name")"
    if [[ -n "$attached_count" && "$attached_count" != "0" ]]; then
      _xmux_error_name_attached "$display_name"
      return 1
    fi
    _xmux_error_name_active "$display_name"
    return 1
  fi

  return 0
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
    node - "$team_dir/team.json" "$team" "$XMUX_LEAD_AGENT" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , filePath, team, lead] = process.argv;
fs.mkdirSync(path.dirname(filePath), { recursive: true });
const payload = {
  schema: 'xmux.team.v1',
  name: team,
  status: 'active',
  lead: { name: lead, provider: 'codex', pane: null },
  members: {},
};
fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
JS
  fi
}

_xmux_record_lead_pane() {
  local team="$1" pane="$2" session="$3" display_name="${4:-$1}"
  local team_dir
  team_dir="$(_xmux_team_dir "$team")"
  _xmux_ensure_team_files "$team"
  print -r -- "$pane" > "$team_dir/.lead-pane"

  node - "$team_dir/team.json" "$team" "$XMUX_LEAD_AGENT" "$pane" "$session" "$PWD" "$display_name" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , filePath, team, leadName, pane, session, cwd, displayName] = process.argv;
let cfg = { schema: 'xmux.team.v1', name: team, members: {} };
try {
  cfg = JSON.parse(fs.readFileSync(filePath, 'utf8'));
} catch (_) {}

const ts = new Date().toISOString();
cfg.name = cfg.name || team;
cfg.display_name = displayName;
cfg.status = 'active';
cfg.lead = {
  name: leadName,
  provider: 'codex',
  pane,
  session,
  display_name: displayName,
  cwd,
  updated_at: ts,
};
let members = cfg.members;
if (!members || typeof members !== 'object' || Array.isArray(members)) {
  members = {};
  cfg.members = members;
}
const existing = members[leadName] && typeof members[leadName] === 'object' ? members[leadName] : {};
members[leadName] = {
  ...existing,
  name: leadName,
  role: 'lead',
  provider: 'codex',
  backend: existing.backend || 'codex',
  pane,
  active: true,
  updated_at: ts,
};
const tmp = `${filePath}.tmp`;
fs.mkdirSync(path.dirname(filePath), { recursive: true });
fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, filePath);
JS

  tmux set-option -p -t "$pane" @xmux-agent "$XMUX_LEAD_AGENT" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-team "$team" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-display-name "$display_name" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-project-dir "$XMUX_PROJECT_DIR" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-state-dir "$XMUX_STATE_DIR" 2>/dev/null
  tmux set-option -p -t "$pane" @xmux-lead "1" 2>/dev/null
  _xmux_apply_pane_brand_style "$pane" "$XMUX_LEAD_AGENT" codex
  tmux set-option -t "$session" @xmux-team "$team" 2>/dev/null
  tmux set-option -t "$session" @xmux-display-name "$display_name" 2>/dev/null
  tmux set-option -t "$session" @xmux-project-dir "$XMUX_PROJECT_DIR" 2>/dev/null
  tmux set-option -t "$session" @xmux-state-dir "$XMUX_STATE_DIR" 2>/dev/null
  _xmux_apply_session_brand_status "$session" "$team" "$display_name"
  _xmux_record_active_team_registry "$team" "$pane" "$session" "$display_name" || true
}

_xmux_mailbox_init_team() {
  local team="$1" pane="$2" session="$3" display_name="${4:-$1}"
  local ran=0

  if _xmux_mailbox_cli init-team "$team" \
      --lead-name "$XMUX_LEAD_AGENT" \
      --lead-provider codex \
      --lead-pane "$pane" >/dev/null 2>&1; then
    ran=1
  else
    echo "[xmux] warning: mailbox init-team failed; using local file scaffold." >&2
  fi

  _xmux_ensure_team_files "$team"
  _xmux_record_lead_pane "$team" "$pane" "$session" "$display_name"

  if (( ran == 0 )); then
    echo "[xmux] warning: mailbox backend unavailable; created local file scaffold only." >&2
  fi
}

_xmux_register_member() {
  local team="$1" agent="$2" provider="$3" pane="$4"
  local team_dir inbox_dir ran
  team_dir="$(_xmux_team_dir "$team")"
  inbox_dir="$team_dir/inboxes"
  ran=0

  mkdir -p "$inbox_dir"
  [[ -f "$inbox_dir/$agent.json" ]] || print -r -- '[]' > "$inbox_dir/$agent.json"
  [[ -f "$inbox_dir/$XMUX_LEAD_AGENT.json" ]] || print -r -- '[]' > "$inbox_dir/$XMUX_LEAD_AGENT.json"

  if _xmux_mailbox_cli register-member "$team" "$agent" \
      --provider "$provider" \
      --backend tmux \
      --pane "$pane" >/dev/null 2>&1; then
    ran=1
  fi

  node - "$team_dir/team.json" "$team" "$agent" "$provider" "$pane" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , filePath, team, agent, provider, pane] = process.argv;
let cfg = { schema: 'xmux.team.v1', name: team, lead: {}, members: {} };
try {
  cfg = JSON.parse(fs.readFileSync(filePath, 'utf8'));
} catch (_) {}
let members = cfg.members;
if (!members || typeof members !== 'object' || Array.isArray(members)) {
  members = {};
  cfg.members = members;
}
const ts = new Date().toISOString();
const entry = {
  name: agent,
  role: 'member',
  provider,
  backend: 'tmux',
  pane,
  active: true,
  updated_at: ts,
};
const existing = members[agent] && typeof members[agent] === 'object' ? members[agent] : {};
members[agent] = { ...existing, ...entry };
cfg.name = cfg.name || team;
const tmp = `${filePath}.tmp`;
fs.mkdirSync(path.dirname(filePath), { recursive: true });
fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, filePath);
JS

  print -r -- "$pane" > "$team_dir/.${agent}-pane"
  if (( ran == 0 )) && [[ -f "$script" ]]; then
    echo "[xmux] warning: mailbox member registration fell back to local config for '$agent'." >&2
  fi
}

_xmux_current_team() {
  local team=""
  if [[ -n "${TMUX:-}" ]]; then
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

  if [[ -n "${TMUX_PANE:-}" ]]; then
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
      [[ "$command_line" == *"xmux-legacy-bridge.zsh"* ]] || return 1
      [[ "$command_line" == *"$team"* && "$command_line" == *"$agent"* ]]
      ;;
    http-mcp)
      return 1
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
  local install_dir project_dir state_dir
  install_dir="$(_xmux_mcp_install_dir)"
  project_dir="$XMUX_PROJECT_DIR"
  state_dir="$XMUX_STATE_DIR"
  node - "$metadata_file" "$team" "$agent" "$port" "$server_path" "$pid" "$install_dir" "$project_dir" "$state_dir" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , metadataFile, team, agent, port, serverPath, pid, installDir, projectDir, stateDir] = process.argv;
const metadata = {
  team,
  agent,
  port,
  server_path: serverPath,
  pid,
  install_dir: installDir,
  project_dir: projectDir,
  state_dir: stateDir,
  updated_at: new Date().toISOString(),
};
fs.mkdirSync(path.dirname(metadataFile), { recursive: true });
const tmp = `${metadataFile}.tmp`;
fs.writeFileSync(tmp, `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, metadataFile);
JS
}

_xmux_http_mcp_pid_matches_metadata() {
  local pid_file="$1" pid="$2" command_line="$3" team="$4" agent="$5"
  local metadata_file expected_server expected_install expected_project expected_state
  metadata_file="$(_xmux_http_mcp_metadata_file "$pid_file")"
  [[ -f "$metadata_file" ]] || return 1
  expected_server="$(_xmux_mcp_bridge_identity)"
  expected_install="$(_xmux_mcp_install_dir)"
  expected_project="$XMUX_PROJECT_DIR"
  expected_state="$XMUX_STATE_DIR"
  node - "$metadata_file" "$pid" "$command_line" "$team" "$agent" "$expected_server" "$expected_install" "$expected_project" "$expected_state" <<'JS'
const fs = require('fs');
const path = require('path');

const [
  ,,
  metadataFile,
  pid,
  commandLine,
  team,
  agent,
  expectedServer,
  expectedInstall,
  expectedProject,
  expectedState,
] = process.argv;
let metadata;
try {
  metadata = JSON.parse(fs.readFileSync(metadataFile, 'utf8'));
} catch (_) {
  process.exit(1);
}

if (metadata.team !== team || metadata.agent !== agent) {
  process.exit(1);
}
if (String(metadata.pid || '') !== String(pid)) {
  process.exit(1);
}
if (path.resolve(String(metadata.server_path || '')) !== path.resolve(expectedServer)) {
  process.exit(1);
}
if (path.resolve(String(metadata.install_dir || '')) !== path.resolve(expectedInstall)) {
  process.exit(1);
}
if (path.resolve(String(metadata.project_dir || '')) !== path.resolve(expectedProject)) {
  process.exit(1);
}
if (path.resolve(String(metadata.state_dir || '')) !== path.resolve(expectedState)) {
  process.exit(1);
}

const serverPath = String(metadata.server_path || '');
const serverName = path.basename(serverPath) || 'bridge.js';
const port = String(metadata.port || '');
if (!commandLine.includes(expectedServer) || !commandLine.includes(serverName) || !commandLine.includes('--http')) {
  process.exit(1);
}
if (port && !commandLine.includes(port)) {
  process.exit(1);
}
process.exit(0);
JS
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
      echo "[xmux] warning: removing stale HTTP MCP pid metadata for disabled $label." >&2
      rm -f "$pid_file" "${metadata_file:-}"
      return 1
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
  local pid meta_pid meta_team meta_agent meta_kind meta_install meta_project meta_state
  [[ -f "$pid_file" && -f "$meta_file" ]] || return 1
  pid=$(< "$pid_file")
  meta_pid="$(_xmux_pid_meta_value "$meta_file" pid 2>/dev/null)"
  meta_team="$(_xmux_pid_meta_value "$meta_file" team 2>/dev/null)"
  meta_agent="$(_xmux_pid_meta_value "$meta_file" agent 2>/dev/null)"
  meta_kind="$(_xmux_pid_meta_value "$meta_file" kind 2>/dev/null)"
  meta_install="$(_xmux_pid_meta_value "$meta_file" install_dir 2>/dev/null)"
  meta_project="$(_xmux_pid_meta_value "$meta_file" project_dir 2>/dev/null)"
  meta_state="$(_xmux_pid_meta_value "$meta_file" state_dir 2>/dev/null)"
  [[ "$pid" == "$meta_pid" \
    && "$meta_team" == "$team" \
    && "$meta_agent" == "$agent" \
    && "$meta_kind" == "$kind" \
    && "$meta_install" == "$XMUX_INSTALL_DIR" \
    && "$meta_project" == "$XMUX_PROJECT_DIR" \
    && "$meta_state" == "$XMUX_STATE_DIR" ]]
}

_xmux_pid_process_matches() {
  local pid="$1" team="$2" agent="$3" kind="$4"
  local command_line outbox
  command_line="$(ps -p "$pid" -o command= 2>/dev/null)" || return 1
  case "$kind" in
    bridge)
      return 1
      ;;
    http_mcp)
      outbox="$(_xmux_team_dir "$team")/inboxes/$XMUX_LEAD_AGENT.json"
      [[ "$command_line" == *"$(_xmux_mcp_bridge_identity)"* && "$command_line" == *"--outbox $outbox"* && "$command_line" == *"--agent $agent"* ]]
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
  print -r -- "$(_xmux_q "team=$team") $(_xmux_q "agent=$agent") $(_xmux_q "kind=$kind") $(_xmux_q "install_dir=$XMUX_INSTALL_DIR") $(_xmux_q "project_dir=$XMUX_PROJECT_DIR") $(_xmux_q "state_dir=$XMUX_STATE_DIR") \"pid=\$pid\""
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

_xmux_pid_runtime_mismatch_message() {
  local meta_file="$1" kind="$2"
  local actual_install actual_project actual_state expected_install
  [[ -f "$meta_file" ]] || return 1
  if [[ "$kind" == "http_mcp" ]]; then
    node - "$meta_file" "$(_xmux_mcp_install_dir)" "$XMUX_PROJECT_DIR" "$XMUX_STATE_DIR" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , metadataFile, expectedInstall, expectedProject, expectedState] = process.argv;
let metadata;
try {
  metadata = JSON.parse(fs.readFileSync(metadataFile, 'utf8'));
} catch (_) {
  process.exit(1);
}
const checks = [
  ['install_dir', metadata.install_dir, expectedInstall],
  ['project_dir', metadata.project_dir, expectedProject],
  ['state_dir', metadata.state_dir, expectedState],
];
for (const [name, actual, expected] of checks) {
  if (actual && path.resolve(String(actual)) !== path.resolve(String(expected))) {
    process.stdout.write(`http_mcp runtime mismatch: ${name}=${actual} expected=${expected}\n`);
    process.exit(0);
  }
}
process.exit(1);
JS
    return $?
  fi
  actual_install="$(_xmux_pid_meta_value "$meta_file" install_dir 2>/dev/null || true)"
  actual_project="$(_xmux_pid_meta_value "$meta_file" project_dir 2>/dev/null || true)"
  actual_state="$(_xmux_pid_meta_value "$meta_file" state_dir 2>/dev/null || true)"
  case "$kind" in
    bridge) expected_install="$XMUX_INSTALL_DIR" ;;
    http_mcp) expected_install="$(_xmux_mcp_install_dir)" ;;
    *) expected_install="$XMUX_INSTALL_DIR" ;;
  esac
  if [[ -n "$actual_install" && "$actual_install" != "$expected_install" ]]; then
    print -r -- "$kind runtime mismatch: install_dir=$actual_install expected=$expected_install"
    return 0
  fi
  if [[ -n "$actual_project" && "$actual_project" != "$XMUX_PROJECT_DIR" ]]; then
    print -r -- "$kind runtime mismatch: project_dir=$actual_project expected=$XMUX_PROJECT_DIR"
    return 0
  fi
  if [[ -n "$actual_state" && "$actual_state" != "$XMUX_STATE_DIR" ]]; then
    print -r -- "$kind runtime mismatch: state_dir=$actual_state expected=$XMUX_STATE_DIR"
    return 0
  fi
  return 1
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
  node - "$target" "$source" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , target, source] = process.argv;
const begin = '<!-- XMUX_PROTOCOL_BEGIN -->';
const end = '<!-- XMUX_PROTOCOL_END -->';

let template;
try {
  template = fs.readFileSync(source, 'utf8').trim();
} catch (_) {
  process.stdout.write('missing-source\n');
  process.exit(1);
}

const block = `${begin}\n${template}\n${end}\n`;
let original = null;
try {
  original = fs.readFileSync(target, 'utf8');
} catch (err) {
  if (!err || err.code !== 'ENOENT') {
    process.stdout.write('read-failed\n');
    process.exit(1);
  }
}

let newText;
let action;
if (original === null) {
  newText = block;
  action = 'created';
} else {
  const start = original.indexOf(begin);
  const stopStart = start >= 0 ? original.indexOf(end, start + begin.length) : -1;
  if (start >= 0 && stopStart >= 0) {
    const stop = stopStart + end.length;
    const current = original.slice(start, stop);
    const desired = block.replace(/\n$/, '');
    if (current.trim() === desired.trim()) {
      process.stdout.write('exists\n');
      process.exit(0);
    }
    newText = `${original.slice(0, start)}${desired}${original.slice(stop)}`;
    if (!newText.endsWith('\n')) {
      newText += '\n';
    }
    action = 'refreshed';
  } else {
    const prefix = original.replace(/\s+$/, '');
    newText = prefix ? `${prefix}\n\n${block}` : block;
    action = 'updated';
  }
}

const parent = path.dirname(target);
const tmp = `${target}.${process.pid}.tmp`;
try {
  if (parent) {
    fs.mkdirSync(parent, { recursive: true });
  }
  fs.writeFileSync(tmp, newText, 'utf8');
  fs.renameSync(tmp, target);
} catch (_) {
  try {
    fs.unlinkSync(tmp);
  } catch (_) {}
  process.stdout.write('write-failed\n');
  process.exit(1);
}

process.stdout.write(`${action}\n`);
JS
}

_xmux_protocol_file_has_block() {
  local target="$1" source="$2"
  [[ -f "$target" && -f "$source" ]] || return 1
  node - "$target" "$source" <<'JS'
const fs = require('fs');

const [, , target, source] = process.argv;
const begin = '<!-- XMUX_PROTOCOL_BEGIN -->';
const end = '<!-- XMUX_PROTOCOL_END -->';

let text;
let template;
try {
  text = fs.readFileSync(target, 'utf8');
  template = fs.readFileSync(source, 'utf8').trim();
} catch (_) {
  process.exit(1);
}

const start = text.indexOf(begin);
const stop = start >= 0 ? text.indexOf(end, start + begin.length) : -1;
if (start < 0 || stop < 0) {
  process.exit(1);
}
const body = text.slice(start + begin.length, stop).trim();
if (body !== template) {
  process.exit(1);
}
if (!body.includes('write_to_lead') || !body.includes('request_id')) {
  process.exit(1);
}
process.exit(0);
JS
}

_xmux_copilot_config_url() {
  node - <<'JS'
const fs = require('fs');
const path = require('path');

const cfgPath = path.join(process.env.HOME || '', '.copilot', 'mcp-config.json');
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(0);
}
const server = ((cfg && cfg.mcpServers) || {}).xmux_bridge || {};
if (server.type === 'sse' && server.url) {
  process.stdout.write(`${server.url}\n`);
}
JS
}

_xmux_gemini_config_has_bridge() {
  local expected="$1"
  node - "$expected" "$(_xmux_mcp_npx_prefix)" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , expected, npxPrefix] = process.argv;
const cfgPath = path.join(process.env.HOME || '', '.gemini', 'settings.json');
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}
const server = ((cfg && cfg.mcpServers) || {}).xmux_bridge;
if (!server || typeof server !== 'object' || Array.isArray(server) || !Array.isArray(server.args)) {
  process.exit(1);
}
const args = server.args;
if (expected === 'npx' && server.command === 'npx'
  && args.some((item, index) => item === '--prefix' && args[index + 1] === npxPrefix)
  && args.includes('xmux')
  && !args.includes('-p')
  && !args.includes('--package')) {
  process.exit(0);
}
if (server.command === 'node' && args[0] === expected) {
  process.exit(0);
}
process.exit(1);
JS
}

_xmux_claude_config_has_bridge() {
  local expected="$1" project_dir="$2" outbox="$3" agent="$4" team="$5"
  node - "$expected" "$project_dir" "$outbox" "$agent" "$team" "$XMUX_STATE_DIR" "$(_xmux_mcp_install_dir)" "$(_xmux_mcp_npx_prefix)" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , expected, projectDirRaw, outboxRaw, agent, team, stateDirRaw, installDirRaw, npxPrefix] = process.argv;
const expand = (value) => {
  if (!value.startsWith('~')) {
    return value;
  }
  const home = process.env.HOME || '';
  if (value === '~') {
    return home;
  }
  if (value.startsWith('~/')) {
    return path.join(home, value.slice(2));
  }
  return value;
};
const projectDir = path.resolve(expand(projectDirRaw));
const outbox = path.resolve(expand(outboxRaw));
const stateDir = path.resolve(expand(stateDirRaw));
const installDir = path.resolve(expand(installDirRaw));
const cfgPath = path.join(process.env.HOME || '', '.claude.json');
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}
const server = ((((cfg || {}).projects || {})[projectDir] || {}).mcpServers || {}).xmux_bridge;
if (!server || typeof server !== 'object' || Array.isArray(server)) {
  process.exit(1);
}
const env = server.env || {};
const args = server.args || [];
const envMatches = env.XMUX_OUTBOX === outbox
  && env.XMUX_AGENT === agent
  && env.XMUX_TEAM === team
  && env.XMUX_STATE_DIR === stateDir
  && env.XMUX_INSTALL_DIR === installDir;
if (!Array.isArray(args) || !envMatches) {
  process.exit(1);
}
if (expected === 'npx') {
  const required = ['xmux', '--outbox', outbox, '--agent', agent, '--team', team];
  const hasPrefix = args.some((item, index) => item === '--prefix' && args[index + 1] === npxPrefix);
  const hasPackageInstall = args.includes('-p') || args.includes('--package');
  if (server.command === 'npx' && hasPrefix && !hasPackageInstall && required.every((item) => args.includes(item))) {
    process.exit(0);
  }
} else if (
  server.command === 'node'
  && JSON.stringify(args.slice(0, 7)) === JSON.stringify([expected, '--outbox', outbox, '--agent', agent, '--team', team])
) {
    process.exit(0);
}
process.exit(1);
JS
}

_xmux_target_json() {
  local agent="$1" provider="$2" pane_id="$3" pane_state="$4"
  local bridge_state="$5" bridge_pid="$6" http_state="$7" http_pid="$8"
  local mailbox_state="$9" ready="${10}" actions_text="${11}" issues_text="${12}"
  node - "$agent" "$provider" "$pane_id" "$pane_state" "$bridge_state" "$bridge_pid" \
    "$http_state" "$http_pid" "$mailbox_state" "$ready" "$actions_text" "$issues_text" <<'JS'
const [
  ,
  ,
  agent,
  provider,
  paneId,
  paneState,
  bridgeState,
  bridgePid,
  httpState,
  httpPid,
  mailboxState,
  ready,
  actionsText,
  issuesText,
] = process.argv;

const cleanPid = (value) => (/^\d+$/.test(value || '') ? Number(value) : null);
const cleanId = (value) => (value === '' || value === '-' ? null : value);
const sep = '\x1f';
const record = {
  agent,
  provider,
  pane: { id: cleanId(paneId), state: paneState },
  bridge: { state: bridgeState, pid: cleanPid(bridgePid) },
  http_mcp: { state: httpState, pid: cleanPid(httpPid) },
  mailbox: { state: mailboxState },
  ready: ready === 'true',
  actions: (actionsText || '').split(sep).filter(Boolean),
  issues: (issuesText || '').split(sep).filter(Boolean),
};
process.stdout.write(`${JSON.stringify(record)}\n`);
JS
}

_xmux_ensure_json() {
  local team="$1" ready="$2"
  shift 2
  node - "$team" "$ready" "$@" <<'JS'
const [, , team, ready, ...targetsRaw] = process.argv;
const targets = targetsRaw.map((item) => JSON.parse(item));
const payload = { team, ready: ready === 'true', targets };
process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
JS
}

_xmux_ensure_human() {
  local team="$1" ready="$2"
  shift 2
  node - "$team" "$ready" "$@" <<'JS'
const [, , team, ready, ...targetsRaw] = process.argv;
const targets = targetsRaw.map((item) => JSON.parse(item));
process.stdout.write(`XMux ensure team=${team} ready=${ready}\n`);
if (targets.length === 0) {
  process.stdout.write('(no targets)\n');
  process.exit(0);
}
process.stdout.write('AGENT                PROVIDER   PANE       BRIDGE       HTTP-MCP     READY ISSUES\n');
for (const item of targets) {
  const pane = item.pane || {};
  const bridge = item.bridge || {};
  const http = item.http_mcp || {};
  const paneText = `${pane.state}:${pane.id || '-'}`;
  const bridgeText = `${bridge.state}:${bridge.pid || '-'}`;
  const httpText = `${http.state}:${http.pid || '-'}`;
  const issues = (item.issues || []).join(', ');
  const row = `${String(item.agent || '-').padEnd(20)} ${String(item.provider || '-').padEnd(10)} `
    + `${paneText.padEnd(10)} ${bridgeText.padEnd(12)} ${httpText.padEnd(12)} `
    + `${String(Boolean(item.ready)).toLowerCase().padEnd(5)} ${issues}`;
  process.stdout.write(`${row}\n`);
}
JS
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
  node - "$XMUX_STATE_DIR" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , root] = process.argv;
const teamsDir = path.join(root, 'teams');
if (!fs.existsSync(teamsDir) || !fs.statSync(teamsDir).isDirectory()) {
  process.exit(0);
}
const inactive = new Set(['archived', 'shutdown', 'inactive', 'deleted']);
const dirs = fs.readdirSync(teamsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();
for (const name of dirs) {
  const cfgPath = path.join(teamsDir, name, 'team.json');
  let cfg;
  try {
    cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  } catch (_) {
    continue;
  }
  const status = String((cfg || {}).status || 'active');
  if (!inactive.has(status)) {
    process.stdout.write(`${name}\n`);
  }
}
JS
}

_xmux_team_is_active() {
  local team="$1"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1
  node - "$cfg" <<'JS'
const fs = require('fs');

const [, , cfgPath] = process.argv;
const inactive = new Set(['archived', 'shutdown', 'inactive', 'deleted']);
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}
const status = String((cfg || {}).status || 'active');
process.exit(inactive.has(status) ? 1 : 0);
JS
}

_xmux_member_field() {
  local team="$1" agent="$2" field="$3"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  node - "$cfg" "$agent" "$field" <<'JS'
const fs = require('fs');

const [, , cfgPath, agent, field] = process.argv;
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}

const members = ((cfg || {}).members && typeof cfg.members === 'object' && !Array.isArray(cfg.members))
  ? cfg.members
  : {};
const lead = ((cfg || {}).lead && typeof cfg.lead === 'object' && !Array.isArray(cfg.lead))
  ? cfg.lead
  : {};
let entry = members[agent];
if (entry === undefined && lead.name === agent) {
  entry = lead;
}
if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
  process.exit(1);
}
let value = entry[field];
if ((value === undefined || value === null) && field === 'session' && lead.name === agent) {
  value = lead.session;
}
if (value === undefined || value === null) {
  value = '';
}
process.stdout.write(`${String(value)}\n`);
JS
}

_xmux_emit_member_records() {
  local team="$1" active_only="${2:-0}"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  node - "$cfg" "$team" "$active_only" <<'JS'
const fs = require('fs');

const [, , cfgPath, team, activeOnly] = process.argv;
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}

const lead = (cfg && cfg.lead && typeof cfg.lead === 'object' && !Array.isArray(cfg.lead)) ? cfg.lead : {};
const members = (cfg && cfg.members && typeof cfg.members === 'object' && !Array.isArray(cfg.members))
  ? { ...cfg.members }
  : {};
const leadName = lead.name;
if (leadName && !Object.prototype.hasOwnProperty.call(members, leadName)) {
  members[leadName] = {
    name: leadName,
    role: 'lead',
    provider: lead.provider || 'codex',
    pane: lead.pane,
    session: lead.session,
    active: true,
  };
}

const clean = (value) => {
  if (value === null || value === undefined || value === '') {
    return '-';
  }
  const text = String(value).replace(/\t/g, ' ').replace(/\n/g, ' ');
  return text || '-';
};

const rows = [];
for (const [name, entry] of Object.entries(members)) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    continue;
  }
  const role = entry.role || (name === leadName ? 'lead' : 'member');
  if (role === 'lead') {
    continue;
  }
  const active = Object.prototype.hasOwnProperty.call(entry, 'active') ? entry.active : true;
  if (activeOnly === '1' && active === false) {
    continue;
  }
  rows.push([
    clean(name),
    [
      clean(team),
      clean(name),
      clean(role),
      clean(entry.provider),
      active !== false ? 'true' : 'false',
      clean(entry.pane),
      clean(entry.session),
      clean(entry.display_mode || entry.mode || 'split'),
      clean(entry.updated_at),
    ],
  ]);
}

rows.sort((a, b) => a[0].localeCompare(b[0]));
for (const [, values] of rows) {
  process.stdout.write(`${values.join('\t')}\n`);
}
JS
}

_xmux_member_record_for_target() {
  local team="$1" target="$2"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1

  node - "$cfg" "$team" "$target" <<'JS'
const fs = require('fs');

const [, , cfgPath, team, target] = process.argv;
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}

const lead = (cfg && cfg.lead && typeof cfg.lead === 'object' && !Array.isArray(cfg.lead)) ? cfg.lead : {};
const members = (cfg && cfg.members && typeof cfg.members === 'object' && !Array.isArray(cfg.members))
  ? { ...cfg.members }
  : {};
const leadName = lead.name;
if (leadName && !Object.prototype.hasOwnProperty.call(members, leadName)) {
  members[leadName] = {
    name: leadName,
    role: 'lead',
    provider: lead.provider || 'codex',
    pane: lead.pane,
    session: lead.session,
    active: true,
  };
}

const clean = (value) => {
  if (value === null || value === undefined || value === '') {
    return '-';
  }
  const text = String(value).replace(/\t/g, ' ').replace(/\n/g, ' ');
  return text || '-';
};

const rows = [];
for (const [name, entry] of Object.entries(members)) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    continue;
  }
  const pane = entry.pane;
  if (name !== target && pane !== target) {
    continue;
  }
  const role = entry.role || (name === leadName ? 'lead' : 'member');
  const active = Object.prototype.hasOwnProperty.call(entry, 'active') ? entry.active : true;
  let session = entry.session;
  if (role === 'lead') {
    session = session || lead.session;
  }
  rows.push([
    role === 'lead' ? 0 : 1,
    clean(name),
    [
      clean(team),
      clean(name),
      clean(role),
      clean(entry.provider),
      active !== false ? 'true' : 'false',
      clean(pane),
      clean(session),
      clean(entry.display_mode || entry.mode || 'split'),
      clean(entry.updated_at),
    ],
  ]);
}

rows.sort((a, b) => {
  if (a[0] !== b[0]) {
    return a[0] - b[0];
  }
  return a[1].localeCompare(b[1]);
});
for (const [, , values] of rows) {
  process.stdout.write(`${values.join('\t')}\n`);
}
JS
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

  node - "$cfg" "$team" <<'JS'
const fs = require('fs');

const [, , cfgPath, team] = process.argv;
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(1);
}

const lead = (cfg && cfg.lead && typeof cfg.lead === 'object' && !Array.isArray(cfg.lead)) ? cfg.lead : {};
const members = (cfg && cfg.members && typeof cfg.members === 'object' && !Array.isArray(cfg.members))
  ? { ...cfg.members }
  : {};
const leadName = lead.name;
if (leadName && !Object.prototype.hasOwnProperty.call(members, leadName)) {
  members[leadName] = {
    name: leadName,
    role: 'lead',
    provider: lead.provider || 'codex',
    pane: lead.pane,
    session: lead.session,
    active: true,
  };
}

const clean = (value) => {
  if (value === null || value === undefined || value === '') {
    return '-';
  }
  const text = String(value).replace(/\t/g, ' ').replace(/\n/g, ' ');
  return text || '-';
};

const rows = [];
for (const [name, entry] of Object.entries(members)) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    continue;
  }
  const role = entry.role || (name === leadName ? 'lead' : 'member');
  const session = role === 'lead' ? (entry.session || lead.session) : entry.session;
  rows.push([
    role === 'lead' ? 0 : 1,
    name,
    [
      clean(team),
      clean(name),
      clean(role),
      clean(entry.provider),
      entry.active === false ? 'false' : 'true',
      clean(entry.pane),
      clean(session),
      clean(entry.display_mode || entry.mode || 'split'),
      clean(entry.updated_at),
    ],
  ]);
}

rows.sort((a, b) => {
  if (a[0] !== b[0]) {
    return a[0] - b[0];
  }
  return String(a[1]).localeCompare(String(b[1]));
});
for (const [, , values] of rows) {
  process.stdout.write(`${values.join('\t')}\n`);
}
JS
}

_xmux_session_for_team() {
  local team="$1"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  local session s

  if [[ -f "$cfg" ]]; then
    session=$(node - "$cfg" <<'JS'
const fs = require('fs');

const [, , cfgPath] = process.argv;
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(0);
}
const lead = (cfg && cfg.lead && typeof cfg.lead === 'object' && !Array.isArray(cfg.lead)) ? cfg.lead : {};
process.stdout.write(`${lead.session || ''}\n`);
JS
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

_xmux_display_name_for_team() {
  local team="$1" session="${2:-}"
  local cfg="$(_xmux_team_dir "$team")/team.json"
  local display_name=""

  if [[ -f "$cfg" ]]; then
    display_name=$(node - "$cfg" <<'JS'
const fs = require('fs');

const [, , cfgPath] = process.argv;
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
} catch (_) {
  process.exit(0);
}
process.stdout.write(`${String((cfg || {}).display_name || '')}\n`);
JS
)
    if [[ -n "$display_name" ]]; then
      print -r -- "$display_name"
      return 0
    fi
  fi

  if [[ -n "$session" ]] && command -v tmux &>/dev/null; then
    display_name=$(tmux show-option -v -t "$session" @xmux-display-name 2>/dev/null || true)
    if [[ -n "$display_name" ]]; then
      print -r -- "$display_name"
      return 0
    fi
  fi

  return 1
}

_xmux_team_for_display_name() {
  local display_name="$1"
  local team="" session="" session_display="" state_matches_raw=""
  local cfg_path="" owner_session=""
  local -a state_matches live_state_matches fallback_matches all_matches unique_matches sorted_matches
  local -A seen_matches
  [[ -n "$display_name" ]] || return 1

  state_matches_raw=$(node - "$XMUX_STATE_DIR" "$display_name" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , root, target] = process.argv;
const teamsDir = path.join(root, 'teams');
if (!fs.existsSync(teamsDir) || !fs.statSync(teamsDir).isDirectory()) {
  process.exit(0);
}
const inactive = new Set(['archived', 'shutdown', 'inactive', 'deleted']);
const matches = new Set();
const dirs = fs.readdirSync(teamsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();
for (const dirName of dirs) {
  const cfgPath = path.join(teamsDir, dirName, 'team.json');
  let cfg;
  try {
    cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  } catch (_) {
    continue;
  }
  const status = String((cfg || {}).status || 'active');
  if (inactive.has(status)) {
    continue;
  }
  const display = String((cfg || {}).display_name || '');
  const name = String((cfg || {}).name || dirName);
  if (display === target || (!display && name === target)) {
    matches.add(dirName);
  }
}
for (const teamName of Array.from(matches).sort()) {
  process.stdout.write(`${teamName}\n`);
}
JS
)
  state_matches=("${(@f)state_matches_raw}")

  if command -v tmux &>/dev/null; then
    for team in "${state_matches[@]}"; do
      [[ -n "$team" ]] || continue
      owner_session="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" session 2>/dev/null || true)"
      if [[ -n "$owner_session" && "$owner_session" != "-" ]] \
        && tmux has-session -t "$owner_session" 2>/dev/null \
        && _xmux_session_owned_by_team "$owner_session" "$team"; then
        live_state_matches+=("$team")
      fi
    done
    state_matches=("${live_state_matches[@]}")
  fi

  if command -v tmux &>/dev/null; then
    while IFS= read -r session; do
      [[ -n "$session" ]] || continue
      session_display=$(tmux show-option -v -t "$session" @xmux-display-name 2>/dev/null || true)
      [[ "$session_display" == "$display_name" ]] || continue
      team=$(tmux show-option -v -t "$session" @xmux-team 2>/dev/null || true)
      [[ -n "$team" ]] || continue
      cfg_path="$(_xmux_team_dir "$team")/team.json"
      if [[ -f "$cfg_path" ]] && ! _xmux_team_is_active "$team"; then
        continue
      fi
      if [[ -f "$cfg_path" ]]; then
        owner_session="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" session 2>/dev/null || true)"
        if [[ -n "$owner_session" && "$owner_session" != "-" && "$owner_session" != "$session" ]]; then
          continue
        fi
      fi
      _xmux_session_owned_by_team "$session" "$team" || continue
      fallback_matches+=("$team")
    done < <(tmux list-sessions -F '#S' 2>/dev/null)
  fi

  all_matches=("${state_matches[@]}" "${fallback_matches[@]}")
  (( ${#all_matches[@]} > 0 )) || return 1

  for team in "${all_matches[@]}"; do
    [[ -n "$team" ]] || continue
    [[ -n "${seen_matches[$team]:-}" ]] && continue
    seen_matches[$team]=1
    unique_matches+=("$team")
  done
  (( ${#unique_matches[@]} > 0 )) || return 1
  sorted_matches=("${(@o)unique_matches}")
  if (( ${#sorted_matches[@]} == 1 )); then
    print -r -- "${sorted_matches[1]}"
    return 0
  fi
  _xmux_error_name_ambiguous "$display_name" "${(j:, :)sorted_matches}"
  return 2
}

_xmux_resolve_target_to_pane() {
  local target="$1" team_hint="${2:-}"
  local team agent pane session
  local -a matches=()

  _xmux_require_tmux || return 1

  if [[ -z "$target" ]]; then
    if [[ -n "${TMUX_PANE:-}" ]] && _xmux_pane_exists "$TMUX_PANE"; then
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
  local line name attached windows team pane cmd display shown=0
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
    display="$name"
    if [[ -n "$team" ]]; then
      display="$(_xmux_display_name_for_team "$team" "$name" 2>/dev/null || true)"
      [[ -z "$display" ]] && display="$name"
    fi
    if [[ -n "$pattern" ]]; then
      if [[ "$name" != *"$pattern"* && "$team" != *"$pattern"* && "$display" != *"$pattern"* ]]; then
        continue
      fi
    fi
    if [[ "$name" == *:* || "$name" == *.* ]]; then
      pane=""
      cmd=""
    else
      pane=$(tmux list-panes -t "$name" -F '#{?pane_active,#{pane_id},}' 2>/dev/null | grep -v '^$' | head -1)
      cmd=$(tmux display-message -t "${pane:-$name}" -p '#{pane_current_command}' 2>/dev/null || true)
    fi
    printf "%-28s %-18s %-8s %-8s %-8s %s\n" "$display" "${team:--}" "$windows" "$attached" "${pane:--}" "${cmd:--}"
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
        local meta_file
        meta_file="$(_xmux_team_dir "$row_team")/.${name}-bridge.meta"
        if [[ -f "$pid_file" ]]; then
          pid=$(< "$pid_file")
          if kill -0 "$pid" 2>/dev/null; then
            if _xmux_pid_ownership_matches "$pid_file" "$meta_file" "$row_team" "$name" "bridge"; then
              bridge="alive"
            else
              bridge="mismatch"
            fi
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
        echo "Usage: xmux paneInfo [<target>] [-t <team>] [-n <lines>]"
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
  local team="$1" payload source
  source="$(_xmux_mailbox_source 2>/dev/null || print -r -- unavailable)"
  payload="$(_xmux_mailbox_cli team-status "$team" 2>/dev/null)" || {
    echo "mailbox: error reading team-status"
    return 0
  }
  node - "$payload" "$source" <<'JS'
const [, , payloadRaw, source] = process.argv;
const payload = JSON.parse(payloadRaw);
const teamStatus = payload.team_status || payload.status || 'unknown';
process.stdout.write(`mailbox: source=${source || 'unknown'} status=${teamStatus} team_dir=${payload.team_dir || '-'}\n`);
const inboxes = payload.inboxes || {};
const names = Object.keys(inboxes).sort();
if (names.length > 0) {
  const parts = names.map((name) => {
    const entry = inboxes[name] || {};
    return `${name}:${entry.unread || 0}/${entry.total || 0}`;
  });
  process.stdout.write(`inboxes: ${parts.join(', ')}\n`);
} else {
  process.stdout.write('inboxes: none\n');
}
const requests = payload.requests || {};
process.stdout.write(
  `requests: total=${requests.total || 0} pending=${requests.pending || 0} done=${requests.done || 0}\n`,
);
JS
}

_xmux_pending_requests_summary() {
  local team="$1" payload
  payload="$(_xmux_mailbox_cli list-requests "$team" --status pending 2>/dev/null)" || return 0
  node - "$payload" <<'JS'
const [, , payloadRaw] = process.argv;
const payload = JSON.parse(payloadRaw);
const requests = payload.requests || [];
if (requests.length === 0) {
  process.stdout.write('pending requests: none\n');
  process.exit(0);
}

process.stdout.write('pending requests:\n');
for (const req of requests.slice(0, 10)) {
  process.stdout.write(
    `  - id=${req.request_id || '-'} from=${req.from || '-'} to=${req.to || '-'} `
      + `status=${req.status || '-'} updated=${req.updated_at || req.created_at || '-'}\n`,
  );
}
if (requests.length > 10) {
  process.stdout.write(`  ... ${requests.length - 10} more pending requests\n`);
}
JS
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
        echo "Usage: xmux bridgeStatus [-t <team>] [<agent>] [--log-lines <n>]"
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
      if [[ "$bridge_status" == "alive" ]] \
          && ! _xmux_pid_ownership_matches "$pid_file" "$team_dir/.${name}-bridge.meta" "$row_team" "$name" "bridge"; then
        bridge_status="mismatch"
      fi

      http_pid_file="$team_dir/.${name}-mcp-http.pid"
      pid_line="$(_xmux_pid_status "$http_pid_file")"
      http_status="${pid_line%%$'\t'*}"
      http_pid="${pid_line#*$'\t'}"
      if [[ "$http_status" == "alive" ]] \
          && ! _xmux_pid_ownership_matches "$http_pid_file" "$(_xmux_http_mcp_metadata_file "$http_pid_file")" "$row_team" "$name" "http_mcp"; then
        http_status="mismatch"
      fi

      env_file="$team_dir/.bridge-${name}.env"
      idle_pattern="$(_xmux_bridge_env_value "$env_file" XMUX_IDLE_PATTERN 2>/dev/null)"
      [[ -z "$idle_pattern" ]] && idle_pattern="$(_xmux_provider_idle_pattern "$provider")"
      [[ -z "$idle_pattern" ]] && idle_pattern="-"
      submit_delay="$(_xmux_bridge_env_value "$env_file" XMUX_SUBMIT_DELAY 2>/dev/null)"
      [[ -z "$submit_delay" ]] && submit_delay="$(_xmux_provider_submit_delay "$provider")"
      log_file="$(_xmux_bridge_env_value "$env_file" XMUX_BRIDGE_LOG 2>/dev/null)"
      [[ -z "$log_file" ]] && log_file="/tmp/xmux-legacy-bridge-${row_team}-${name}.log"

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

_xmux_cmd_send_pane() {
  _xmux_legacy_teammate_disabled "xmux sendPane"
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

  local session="" pane="" display_name_target="" display_name_team="" display_lookup_rc=0
  if [[ -n "$target" && "$target" == */* ]]; then
    if display_name_team="$(_xmux_team_for_display_name "$target")"; then
      display_lookup_rc=0
    else
      display_lookup_rc=$?
    fi
    if (( display_lookup_rc == 0 )) && [[ -n "$display_name_team" ]]; then
      team="$display_name_team"
      display_name_target="$target"
      session="$(_xmux_session_for_team "$team")" || {
        echo "error: no live tmux session for XMux name '$display_name_target'." >&2
        return 1
      }
    elif (( display_lookup_rc == 2 )); then
      return 1
    fi
  fi

  if [[ -n "$team" && -z "$target" ]]; then
    _xmux_validate_team_name "$team" || return 1
    session="$(_xmux_session_for_team "$team")" || { echo "error: no live tmux session for team '$team'." >&2; return 1; }
  elif [[ -z "$session" && -n "$target" && "$target" != *:* && "$target" != *.* ]] && tmux has-session -t "$target" 2>/dev/null; then
    session="$target"
  elif [[ -z "$session" ]]; then
    pane="$(_xmux_resolve_target_to_pane "$target" "$team")" || return $?
    session=$(tmux display-message -t "$pane" -p '#{session_name}' 2>/dev/null)
  fi

  [[ -n "$session" ]] || { echo "error: cannot resolve tmux session." >&2; return 1; }
  _xmux_validate_session_name "$session" || return 1
  if [[ -n "$display_name_target" ]]; then
    local attached_count
    attached_count="$(_xmux_session_attached_count "$session")"
    if [[ -n "$attached_count" && "$attached_count" != "0" ]]; then
      _xmux_error_name_attached "$display_name_target"
      return 1
    fi
  fi
  [[ -n "$pane" ]] && tmux select-pane -t "$pane" 2>/dev/null
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$session"
  else
    _xmux_attach_session "$session"
  fi
}

_xmux_mark_member_inactive() {
  local team="$1" agent="$2"
  _xmux_mailbox_cli update-member "$team" "$agent" --active false >/dev/null 2>&1 && return 0

  local cfg="$(_xmux_team_dir "$team")/team.json"
  [[ -f "$cfg" ]] || return 1
  node - "$cfg" "$agent" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , cfgPath, agent] = process.argv;
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const members = cfg.members && typeof cfg.members === 'object' && !Array.isArray(cfg.members)
  ? cfg.members
  : {};
cfg.members = members;
if (members[agent] && typeof members[agent] === 'object' && !Array.isArray(members[agent])) {
  const ts = new Date().toISOString();
  members[agent].active = false;
  members[agent].updated_at = ts;
  cfg.updated_at = ts;
  const tmp = `${cfgPath}.tmp`;
  fs.mkdirSync(path.dirname(cfgPath), { recursive: true });
  fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, cfgPath);
}
JS
}

_xmux_mark_team_shutdown_start() {
  local team="$1" reason="$2" team_dir cfg events
  team_dir="$(_xmux_team_dir "$team")"
  cfg="$team_dir/team.json"
  events="$team_dir/events.jsonl"
  [[ -f "$cfg" ]] || return 1
  node - "$cfg" "$events" "$team" "$reason" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , cfgPath, eventsPath, team, reason] = process.argv;
const ts = new Date().toISOString();
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const shutdown = cfg.shutdown && typeof cfg.shutdown === 'object' && !Array.isArray(cfg.shutdown)
  ? { ...cfg.shutdown }
  : {};
shutdown.reason = reason;
shutdown.started_at = shutdown.started_at || ts;
shutdown.status = 'shutting_down';
cfg.shutdown = shutdown;
cfg.status = 'shutting_down';
cfg.updated_at = ts;
const tmp = `${cfgPath}.tmp`;
fs.mkdirSync(path.dirname(cfgPath), { recursive: true });
fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, cfgPath);
const record = {
  ts,
  event: 'team.shutdown_started',
  actor: 'xmux',
  target: team,
  request_id: null,
  data: { reason },
};
fs.mkdirSync(path.dirname(eventsPath), { recursive: true });
fs.appendFileSync(eventsPath, `${JSON.stringify(record)}\n`, 'utf8');
JS
}

_xmux_mark_team_shutdown_complete() {
  local team="$1" reason="$2" shutdown_status="$3" archive_path="${4:-}"
  local team_dir cfg events metadata
  team_dir="$(_xmux_team_dir "$team")"
  cfg="$team_dir/team.json"
  events="$team_dir/events.jsonl"
  metadata="$team_dir/shutdown.json"
  [[ -f "$cfg" ]] || return 1
  node - "$cfg" "$events" "$metadata" "$team" "$reason" "$shutdown_status" "$archive_path" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , cfgPath, eventsPath, metadataPath, team, reason, status, archivePath] = process.argv;
const ts = new Date().toISOString();
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const members = cfg.members && typeof cfg.members === 'object' && !Array.isArray(cfg.members)
  ? cfg.members
  : {};
cfg.members = members;
const leadName = (cfg.lead || {}).name;
for (const [name, entry] of Object.entries(members)) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry) || name === leadName || entry.role === 'lead') {
    continue;
  }
  entry.active = false;
  entry.updated_at = ts;
}
const shutdown = cfg.shutdown && typeof cfg.shutdown === 'object' && !Array.isArray(cfg.shutdown)
  ? { ...cfg.shutdown }
  : {};
delete shutdown.failed_agents;
delete shutdown.failed_at;
shutdown.reason = reason;
shutdown.completed_at = ts;
shutdown.status = status;
if (archivePath) shutdown.archive_path = archivePath;
cfg.shutdown = shutdown;
cfg.status = status;
cfg.updated_at = ts;
const tmp = `${cfgPath}.tmp`;
fs.mkdirSync(path.dirname(cfgPath), { recursive: true });
fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, cfgPath);
const metadata = {
  team,
  reason,
  status,
  shutdown_completed_at: ts,
};
if (archivePath) metadata.archive_path = archivePath;
fs.writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
const record = {
  ts,
  event: 'team.shutdown_completed',
  actor: 'xmux',
  target: team,
  request_id: null,
  data: { reason, status, archive_path: archivePath || null },
};
fs.appendFileSync(eventsPath, `${JSON.stringify(record)}\n`, 'utf8');
JS
}

_xmux_mark_team_shutdown_degraded() {
  local team="$1" reason="$2" failures="$3"
  local team_dir cfg events
  team_dir="$(_xmux_team_dir "$team")"
  cfg="$team_dir/team.json"
  events="$team_dir/events.jsonl"
  [[ -f "$cfg" ]] || return 1
  node - "$cfg" "$events" "$team" "$reason" "$failures" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , cfgPath, eventsPath, team, reason, failures] = process.argv;
const failedAgents = String(failures || '').split(',').filter(Boolean);
const ts = new Date().toISOString();
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const shutdown = cfg.shutdown && typeof cfg.shutdown === 'object' && !Array.isArray(cfg.shutdown)
  ? { ...cfg.shutdown }
  : {};
shutdown.reason = reason;
shutdown.failed_agents = failedAgents;
shutdown.failed_at = ts;
shutdown.status = 'degraded';
cfg.shutdown = shutdown;
cfg.status = 'degraded';
cfg.updated_at = ts;
const tmp = `${cfgPath}.tmp`;
fs.mkdirSync(path.dirname(cfgPath), { recursive: true });
fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
fs.renameSync(tmp, cfgPath);
const record = {
  ts,
  event: 'team.shutdown_degraded',
  actor: 'xmux',
  target: team,
  request_id: null,
  data: { reason, failed_agents: failedAgents },
};
fs.appendFileSync(eventsPath, `${JSON.stringify(record)}\n`, 'utf8');
JS
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
    tmux set-option -u -t "$session" @xmux-display-name 2>/dev/null || true
  fi

  pane="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" pane 2>/dev/null)"
  if [[ -n "$pane" && "$pane" != "-" ]] && _xmux_pane_exists "$pane"; then
    tags=$(tmux display-message -t "$pane" -p '#{@xmux-team}'$'\t''#{@xmux-lead}' 2>/dev/null || true)
    pane_team="${tags%%$'\t'*}"
    is_lead="${tags#*$'\t'}"
    if [[ "$pane_team" == "$team" && "$is_lead" == "1" ]]; then
      tmux set-option -p -u -t "$pane" @xmux-agent 2>/dev/null || true
      tmux set-option -p -u -t "$pane" @xmux-team 2>/dev/null || true
      tmux set-option -p -u -t "$pane" @xmux-display-name 2>/dev/null || true
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
  node - "$archive_dir" "$team" "$reason" <<'JS'
const fs = require('fs');
const path = require('path');

const [, , archiveDir, team, reason] = process.argv;
const ts = new Date().toISOString();
const metadata = {
  team,
  archived_at: ts,
  reason,
  status: 'archived',
};
fs.writeFileSync(path.join(archiveDir, 'archive.json'), `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
const record = {
  ts,
  event: 'team.archived',
  actor: 'xmux',
  target: team,
  request_id: null,
  data: { reason, archive_dir: archiveDir },
};
fs.appendFileSync(path.join(archiveDir, 'events.jsonl'), `${JSON.stringify(record)}\n`, 'utf8');
JS
}

_xmux_archive_team_dir() {
  local team="$1" reason="$2" team_dir archive_root stamp base archive_dir suffix
  team_dir="$(_xmux_team_dir "$team")"
  archive_root="$XMUX_STATE_DIR/archive"
  mkdir -p "$archive_root"
  stamp=$(node -e "const d=new Date(); const p=n=>String(n).padStart(2,'0'); process.stdout.write(String(d.getUTCFullYear())+p(d.getUTCMonth()+1)+p(d.getUTCDate())+'T'+p(d.getUTCHours())+p(d.getUTCMinutes())+p(d.getUTCSeconds())+'Z')")
  base="$archive_root/${stamp}-${team}"
  archive_dir="$base"
  suffix=2
  while [[ -e "$archive_dir" ]]; do
    archive_dir="${base}-${suffix}"
    suffix=$(( suffix + 1 ))
  done
  _xmux_mark_team_shutdown_complete "$team" "$reason" "archived" "$archive_dir" || return 1
  mv "$team_dir" "$archive_dir" || return 1
  _xmux_remove_active_team_registry "$team" || true
  _xmux_write_archive_metadata "$archive_dir" "$team" "$reason"
  print -r -- "$archive_dir"
}

_xmux_free_port() {
  node - <<'JS'
const net = require('net');
const server = net.createServer();
server.listen(0, '127.0.0.1', () => {
  const address = server.address();
  process.stdout.write(`${address.port}\n`);
  server.close();
});
server.on('error', () => process.exit(1));
JS
}

_xmux_start_copilot_mcp() {
  _xmux_legacy_teammate_disabled "Copilot MCP startup"
}

_xmux_prepare_gemini_mcp() {
  _xmux_legacy_teammate_disabled "Gemini MCP setup"
}

_xmux_prepare_claude_mcp() {
  _xmux_legacy_teammate_disabled "Claude MCP setup"
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
  _xmux_legacy_teammate_disabled "teammate bridge startup"
}

_xmux_ensure_one_record() {
  local record="$1" want_bridge="$2" want_ready="$3"
  local team agent role provider active pane session mode updated
  IFS=$'\t' read -r team agent role provider active pane session mode updated <<< "$record"

  local team_dir bridge_pid_file bridge_meta_file http_pid_file http_meta_file http_url_file env_file inbox outbox
  local pane_state bridge_line bridge_state bridge_pid http_line http_state http_pid
  local timeout idle_pattern submit_delay mailbox_state target_ready expected_url config_url
  local sep actions_text issues_text file_state claude_prompt copilot_prompt gemini_prompt cleanup_status cleanup_message cleanup_rc cleanup_failed runtime_message
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
  claude_prompt="$XMUX_PROJECT_DIR/CLAUDE.md"
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
      claude)
        file_state="$(_xmux_ensure_file_from_template "$claude_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/CLAUDE.md" 2>/dev/null)"
        case "$file_state" in
          created) actions+=("created CLAUDE.md") ;;
          updated) actions+=("installed XMux Claude protocol block") ;;
          refreshed) actions+=("refreshed XMux Claude protocol block") ;;
          exists) ;;
          *) issues+=("Claude XMux protocol block missing") ;;
        esac
        _xmux_protocol_file_has_block "$claude_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/CLAUDE.md" \
          || issues+=("Claude XMux protocol block not installed")
        if ! _xmux_claude_config_has_bridge "$(_xmux_mcp_bridge_ref)" "$XMUX_PROJECT_DIR" "$outbox" "$agent" "$team"; then
          if _xmux_prepare_claude_mcp "$team" "$agent" "$outbox" >/dev/null; then
            actions+=("configured Claude MCP bridge")
          else
            issues+=("Claude MCP bridge config failed")
          fi
        fi
        ;;
      copilot)
        file_state="$(_xmux_ensure_file_from_template "$copilot_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/COPILOT.md" 2>/dev/null)"
        case "$file_state" in
          created) actions+=("created .github/copilot-instructions.md") ;;
          updated) actions+=("installed XMux Copilot protocol block") ;;
          refreshed) actions+=("refreshed XMux Copilot protocol block") ;;
          exists) ;;
          *) issues+=("Copilot XMux protocol block missing") ;;
        esac
        _xmux_protocol_file_has_block "$copilot_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/COPILOT.md" \
          || issues+=("Copilot XMux protocol block not installed")
        ;;
      gemini)
        file_state="$(_xmux_ensure_file_from_template "$gemini_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/GEMINI.md" 2>/dev/null)"
        case "$file_state" in
          created) actions+=("created .gemini/GEMINI.md") ;;
          updated) actions+=("installed XMux Gemini protocol block") ;;
          refreshed) actions+=("refreshed XMux Gemini protocol block") ;;
          exists) ;;
          *) issues+=("Gemini XMux protocol block missing") ;;
        esac
        _xmux_protocol_file_has_block "$gemini_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/GEMINI.md" \
          || issues+=("Gemini XMux protocol block not installed")
        if ! _xmux_gemini_config_has_bridge "$(_xmux_mcp_bridge_ref)"; then
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
      runtime_message="$(_xmux_pid_runtime_mismatch_message "$bridge_meta_file" bridge 2>/dev/null || true)"
      [[ -n "$runtime_message" ]] && actions+=("$runtime_message")
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
      runtime_message="$(_xmux_pid_runtime_mismatch_message "$http_meta_file" http_mcp 2>/dev/null || true)"
      [[ -n "$runtime_message" ]] && actions+=("$runtime_message")
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
        issues+=("Copilot MCP config update skipped because legacy MCP is disabled")
      fi
    elif [[ -z "$(_xmux_copilot_config_url 2>/dev/null)" ]]; then
      issues+=("Copilot MCP SSE URL not discoverable")
    fi
  fi

  pane_state="$(_xmux_verified_pane_state "$team" "$agent" "$pane")"
  [[ "$pane_state" == "stale" ]] && issues+=("pane tag mismatch")
  if (( want_ready )) && [[ "$pane_state" == "alive" ]]; then
    _xmux_apply_pane_brand_style "$pane" "$agent" "$provider" >/dev/null 2>&1 \
      || issues+=("pane brand style update failed")
  fi
  if (( want_ready )); then
    [[ -z "$session" || "$session" == "-" ]] && session="$(_xmux_session_for_team "$team" 2>/dev/null)"
    [[ -n "$session" && "$session" != "-" ]] && _xmux_apply_session_brand_status "$session" "$team" "$(_xmux_display_name_for_team "$team" "$session" 2>/dev/null || true)" >/dev/null 2>&1
  fi
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
        _xmux_protocol_file_has_block "$copilot_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/COPILOT.md" || target_ready=0
        if [[ -f "$http_url_file" ]]; then
          expected_url="$(< "$http_url_file")"
          [[ "$(_xmux_copilot_config_url 2>/dev/null)" == "$expected_url" ]] || target_ready=0
        else
          [[ -n "$(_xmux_copilot_config_url 2>/dev/null)" ]] || target_ready=0
        fi
        ;;
      gemini)
        _xmux_protocol_file_has_block "$gemini_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/GEMINI.md" || target_ready=0
        _xmux_gemini_config_has_bridge "$(_xmux_mcp_bridge_ref)" || target_ready=0
        ;;
      claude)
        _xmux_protocol_file_has_block "$claude_prompt" "$XMUX_INSTALL_DIR/runtime/prompt/CLAUDE.md" || target_ready=0
        _xmux_claude_config_has_bridge "$(_xmux_mcp_bridge_ref)" "$XMUX_PROJECT_DIR" "$outbox" "$agent" "$team" || target_ready=0
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
  _xmux_refresh_active_team_registry "$team" || true
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
    _xmux_remove_active_team_registry "$team" || true
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

_xmux_prepare_codex_runtime() {
  local script project_arg
  script="$(_xmux_codex_setup_script 2>/dev/null)" || return 0
  project_arg=()
  if [[ -f "$PWD/.codex/config.toml" ]]; then
    project_arg=(--project "$PWD")
  fi
  if [[ -n "$script" ]]; then
    node "$script" \
      --doctor \
      --quiet \
      "${project_arg[@]}" \
      --xmux-install-dir "$(_xmux_mcp_install_dir)" >/dev/null 2>&1 || {
        echo "[xmux] warning: XMux Codex integration is not configured; run 'xmux setup-codex'." >&2
      }
  fi
}

_xmux_codex_setup_script() {
  local candidate
  for candidate in \
      "$XMUX_INSTALL_DIR/src/codex/setup.js" \
      "$XMUX_INSTALL_DIR/dist/codex/setup.js"; do
    [[ -f "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  echo "error: missing XMux Codex setup script under $XMUX_INSTALL_DIR/src/codex or $XMUX_INSTALL_DIR/dist/codex." >&2
  return 1
}

_xmux_run_codex_setup_script() {
  local script
  script="$(_xmux_codex_setup_script)" || return 1
  node "$script" \
    --xmux-install-dir "$(_xmux_mcp_install_dir)" \
    "$@"
}

_xmux_setup_codex_usage() {
  cat >&2 <<'EOF'
Usage: xmux setup-codex [--with-skills|--without-skills] [--skills-dir <dir>]
       xmux doctor-codex [--quiet] [--skills-dir <dir>]
       xmux remove-codex [--with-skills]
       xmux install-skills [--skills-dir <dir>] [--skill <name>]... [--force|--refresh] [--dry-run] [--from-github] [--ref <tag>]
       xmux remove-skills [--dry-run]
EOF
}

_xmux_cmd_setup_codex() {
  local arg
  local -a setup_args=()
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --with-skills|--without-skills)
        setup_args+=("$arg")
        shift
        ;;
      --home|--project|--skills-dir)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a value." >&2; return 1; }
        setup_args+=("$arg" "$2")
        shift 2
        ;;
      --cache-mcp|--no-cache-mcp|--mcp-package|--mcp-version|--mcp-bin|--mcp-npx-prefix)
        echo "error: $arg is disabled; Codex-Claude communication no longer uses MCP." >&2
        return 1
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
        [[ $# -ge 2 ]] || { echo "error: $arg requires a value." >&2; return 1; }
        doctor_args+=("$arg" "$2")
        shift 2
        ;;
      --mcp-package|--mcp-version|--mcp-bin|--mcp-npx-prefix)
        echo "error: $arg is disabled; doctor-codex no longer probes MCP." >&2
        return 1
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
      --with-skills)
        remove_args+=("$arg")
        shift
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

_xmux_cmd_install_skills() {
  local arg
  local -a install_args=(--install-skills)
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --from-github|--force|--refresh|--dry-run)
        install_args+=("$arg")
        shift
        ;;
      --home|--project|--skills-dir|--skill|--ref)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a value." >&2; return 1; }
        install_args+=("$arg" "$2")
        shift 2
        ;;
      -h|--help)
        _xmux_setup_codex_usage
        return 0
        ;;
      *)
        echo "error: unknown install-skills option '$arg'." >&2
        _xmux_setup_codex_usage
        return 1
        ;;
    esac
  done
  _xmux_run_codex_setup_script "${install_args[@]}"
}

_xmux_cmd_remove_skills() {
  local arg
  local -a remove_args=(--remove-skills)
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --dry-run)
        remove_args+=("$arg")
        shift
        ;;
      --home|--project)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a value." >&2; return 1; }
        remove_args+=("$arg" "$2")
        shift 2
        ;;
      -h|--help)
        _xmux_setup_codex_usage
        return 0
        ;;
      *)
        echo "error: unknown remove-skills option '$arg'." >&2
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
  local codex_home_env rc lead_stdio_ready=0 codex_session_name codex_harness_script
  codex_home_env="$(_xmux_codex_home_env_name)"
  codex_session_name="${XMUX_CODEX_SESSION_NAME:-${XMUX_TEAM:-default}}"
  codex_harness_script="$(_xmux_codex_harness_cli_path 2>/dev/null)" || {
    echo "[xmux] error: missing Codex pane harness." >&2
    return 1
  }
  _xmux_lead_stdio_is_tty && lead_stdio_ready=1
  if [[ -n "${TMUX_PANE:-}" ]]; then
    tmux set-option -pt "$TMUX_PANE" @xmux-codex-session "$codex_session_name" 2>/dev/null || true
  fi
  env -u "$codex_home_env" -u XMUX_DIR -u XMUX_HOME \
    XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    XMUX_TEAM="$XMUX_TEAM" \
    XMUX_CODEX_SESSION_NAME="$codex_session_name" \
    XMUX_AGENT="${XMUX_AGENT:-$XMUX_LEAD_AGENT}" \
    XMUX_TEAM_DIR="$XMUX_TEAM_DIR" \
    node "$codex_harness_script" pane-run --name "$codex_session_name" -- "$@"
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
  wrapper='source "$XMUX_INSTALL_DIR/runtime/shell/xmux.zsh"; _xmux_run_codex_lead "$@"'
  codex_cmd="exec env -u $(_xmux_q "$codex_home_env") -u XMUX_DIR -u XMUX_HOME $env_prefix XMUX_TEAM=$(_xmux_q "$team_name") XMUX_AGENT=$(_xmux_q "$XMUX_LEAD_AGENT") XMUX_TEAM_DIR=$(_xmux_q "$team_dir") XMUX_SHUTDOWN_ON_LEAD_EXIT=$(_xmux_q "$shutdown_on_exit") zsh -lc $(_xmux_q "$wrapper") xmux-lead"
  for arg in "$@"; do
    codex_cmd+=" $(_xmux_q "$arg")"
  done
  print -r -- "$codex_cmd"
}

_xmux_spawn_member() {
  _xmux_refresh_home
  local provider="$1" default_agent="$2" idle_pattern="$3" base_cmd="$4"
  shift 4

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
    if [[ -n "${TMUX:-}" ]]; then
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

  local display_name
  display_name="$(_xmux_display_name_for_team "$team" "$session" 2>/dev/null || print -r -- "$team")"
  _xmux_mailbox_init_team "$team" "$lead_pane" "$session" "$display_name"
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
  if [[ "$provider" == "claude" ]]; then
    _xmux_ensure_file_from_template "$XMUX_PROJECT_DIR/CLAUDE.md" "$XMUX_INSTALL_DIR/runtime/prompt/CLAUDE.md" >/dev/null || {
      echo "error: failed to install Claude XMux protocol block in $XMUX_PROJECT_DIR/CLAUDE.md." >&2
      return 1
    }
    _xmux_prepare_claude_mcp "$team" "$agent" "$outbox" || {
      echo "error: failed to configure Claude MCP bridge in ~/.claude.json." >&2
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
  tmux set-option -p -t "$agent_pane" @xmux-agent "$agent" 2>/dev/null
  tmux set-option -p -t "$agent_pane" @xmux-team "$team" 2>/dev/null
  tmux set-option -p -t "$agent_pane" @xmux-legacy-bridge "1" 2>/dev/null
  _xmux_apply_pane_brand_style "$agent_pane" "$agent" "$provider"
  tmux select-pane -t "$lead_pane" 2>/dev/null

  _xmux_register_member "$team" "$agent" "$provider" "$agent_pane"
  _xmux_start_member_bridge "$team" "$agent" "$provider" "$agent_pane" "$timeout" "$idle_pattern" "$submit_delay" || return 1

  echo "[xmux-${provider}] $agent attached - pane:$agent_pane team:$team"
}

xmux-claude() {
  _xmux_legacy_teammate_disabled "xmux-claude"
}

xmux-gemini() {
  _xmux_legacy_teammate_disabled "xmux-gemini"
}

xmux-copilot() {
  _xmux_legacy_teammate_disabled "xmux-copilot"
}

_xmux_start() {
  _xmux_refresh_home
  local requested_name="" session_name="" team_name="" display_name="" scoped_name_requested=0
  local explicit_team_name=0
  local spawn_claude=0 spawn_gemini=0 spawn_copilot=0
  local shutdown_on_lead_exit="${XMUX_SHUTDOWN_ON_LEAD_EXIT:-1}"
  local -a codex_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        [[ $# -ge 2 ]] || { echo "error: -n requires a session name." >&2; return 1; }
        requested_name="$2"
        shift 2
        ;;
      -T)
        [[ $# -ge 2 ]] || { echo "error: -T requires a team name." >&2; return 1; }
        team_name="$2"
        explicit_team_name=1
        shift 2
        ;;
      --claude)
        echo "error: --claude startup is disabled. Start Codex with xmux, then invoke '\$xmux-claude' from Codex." >&2
        return 1
        ;;
      --gemini)
        echo "error: --gemini startup is disabled in the Claude hook harness." >&2
        return 1
        ;;
      --copilot)
        echo "error: --copilot startup is disabled in the Claude hook harness." >&2
        return 1
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
        echo "error: Codex teammates are unsupported in XMux; Codex is the lead only. Use xmux claude for the Claude hook harness." >&2
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

  if [[ -n "$requested_name" ]]; then
    _xmux_validate_session_name "$requested_name" || return 1
    local resolved_name_fields resolved_team_name resolved_session_name
    resolved_name_fields="$(_xmux_resolve_name_fields "$requested_name")"
    display_name="${resolved_name_fields%%$'\t'*}"
    resolved_name_fields="${resolved_name_fields#*$'\t'}"
    resolved_team_name="${resolved_name_fields%%$'\t'*}"
    resolved_session_name="${resolved_name_fields#*$'\t'}"
    if (( explicit_team_name == 0 )); then
      scoped_name_requested=1
      team_name="$resolved_team_name"
      session_name="$resolved_session_name"
    else
      session_name="$requested_name"
    fi
  fi

  [[ -z "$session_name" ]] && session_name="$(_xmux_default_session_name)"
  [[ -z "$team_name" ]] && team_name="$(_xmux_team_from_session "$session_name")"
  [[ -z "$display_name" ]] && display_name="$team_name"
  _xmux_validate_session_name "$session_name" || return 1
  _xmux_validate_team_name "$team_name" || return 1

  _xmux_require_tmux || return 1
  command -v codex &>/dev/null || { echo "error: codex is not installed." >&2; return 1; }

  local team_dir codex_cmd
  team_dir="$(_xmux_team_dir "$team_name")"
  _xmux_prepare_codex_runtime

  _xmux_guard_scoped_name_available "$scoped_name_requested" "$display_name" "$team_name" "$session_name" || return 1

  if [[ -n "${TMUX:-}" ]] && _xmux_lead_stdio_is_tty; then
    local session lead_pane
    session=$(tmux display-message -p '#S' 2>/dev/null)
    _xmux_validate_session_name "$session" || return 1
    lead_pane="${TMUX_PANE:-}"
    _xmux_mailbox_init_team "$team_name" "$lead_pane" "$session" "$display_name"

    (( spawn_claude )) && xmux-claude -t "$team_name"
    (( spawn_gemini )) && xmux-gemini -t "$team_name"
    (( spawn_copilot )) && xmux-copilot -t "$team_name"

    XMUX_TEAM="$team_name" \
      XMUX_AGENT="$XMUX_LEAD_AGENT" \
      XMUX_TEAM_DIR="$team_dir" \
      XMUX_SHUTDOWN_ON_LEAD_EXIT="$shutdown_on_lead_exit" \
      _xmux_with_terminal_codex_theme _xmux_run_codex_lead "${codex_args[@]}"
    return
  fi

  local session_exists=0
  if tmux has-session -t "$session_name" 2>/dev/null; then
    session_exists=1
  fi

  codex_cmd="$(_xmux_build_codex_env_command "$team_name" "$team_dir" "$shutdown_on_lead_exit" -- "${codex_args[@]}")"

  if (( session_exists == 0 )); then
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
  _xmux_mailbox_init_team "$team_name" "$lead_pane" "$session_name" "$display_name"

  (( spawn_claude )) && _xmux_spawn_member claude claude-worker "" "claude" -t "$team_name" -s "$session_name"
  (( spawn_gemini )) && _xmux_spawn_member gemini gemini-worker "Type your message" "gemini --yolo" -t "$team_name" -s "$session_name"
  (( spawn_copilot )) && _xmux_spawn_member copilot copilot-worker "/ commands" "copilot --yolo --autopilot --max-autopilot-continues 10" -t "$team_name" -s "$session_name"

  if _xmux_lead_stdio_is_tty; then
    _xmux_attach_session "$session_name"
  else
    if (( explicit_team_name == 1 )); then
      echo "[xmux] team created team:$team_name session:$session_name detached:true name:$display_name"
    else
      echo "[xmux] team created name:$display_name team:$team_name session:$session_name detached:true"
    fi
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
    -V|--version|version)
      _xmux_print_version
      ;;
    ""|-*)
      _xmux_start "$@"
      ;;
    start)
      shift
      _xmux_start "$@"
      ;;
    teamCreate)
      shift
      _xmux_legacy_teammate_disabled "xmux teamCreate"
      ;;
    teammateAdd)
      shift
      _xmux_legacy_teammate_disabled "xmux teammateAdd"
      ;;
    teamStatus)
      shift
      _xmux_legacy_teammate_disabled "xmux teamStatus"
      ;;
    teammateStatus)
      shift
      _xmux_legacy_teammate_disabled "xmux teammateStatus"
      ;;
    teammateShutdown)
      shift
      _xmux_legacy_teammate_disabled "xmux teammateShutdown"
      ;;
    teamShutdown)
      shift
      _xmux_legacy_teammate_disabled "xmux teamShutdown"
      ;;
    claude)
      shift
      _xmux_cmd_claude_harness "$@"
      ;;
    gemini)
      shift
      _xmux_legacy_teammate_disabled "xmux gemini"
      ;;
    copilot)
      shift
      _xmux_legacy_teammate_disabled "xmux copilot"
      ;;
    codex|xmux-codex)
      shift
      _xmux_cmd_codex_harness "$@"
      ;;
    codex-"worker")
      echo "error: Codex teammates are unsupported in XMux; Codex is the lead only. Use xmux codex for the Codex pane harness." >&2
      return 1
      ;;
    teammates)
      shift
      _xmux_legacy_teammate_disabled "xmux teammates"
      ;;
    sessions)
      shift
      _xmux_cmd_sessions "$@"
      ;;
    paneInfo)
      shift
      _xmux_cmd_pane_info "$@"
      ;;
    doctor)
      shift
      _xmux_cmd_doctor "$@"
      ;;
    setup-codex)
      shift
      _xmux_cmd_setup_codex "$@"
      ;;
    doctor-codex)
      shift
      _xmux_cmd_doctor_codex "$@"
      ;;
    remove-codex)
      shift
      _xmux_cmd_remove_codex "$@"
      ;;
    install-skills)
      shift
      _xmux_cmd_install_skills "$@"
      ;;
    remove-skills)
      shift
      _xmux_cmd_remove_skills "$@"
      ;;
    theme-reset)
      shift
      _xmux_reset_terminal_theme
      ;;
    bridgeStatus)
      shift
      _xmux_legacy_teammate_disabled "xmux bridgeStatus"
      ;;
    ensure)
      shift
      _xmux_legacy_teammate_disabled "xmux ensure"
      ;;
    recover)
      shift
      _xmux_legacy_teammate_disabled "xmux recover"
      ;;
    sendPane)
      shift
      _xmux_legacy_teammate_disabled "xmux sendPane"
      ;;
    attach)
      shift
      _xmux_cmd_attach "$@"
      ;;
    shutdown)
      shift
      _xmux_cmd_shutdown "$@"
      ;;
    help)
      shift
      _xmux_help "$@"
      ;;
    -h|--help)
      _xmux_user_usage
      ;;
    *)
      echo "error: unknown xmux command '$cmd'." >&2
      _xmux_user_usage
      return 1
      ;;
  esac
}
