# runtime/shell/xmux.zsh - XMux Codex-Claude hook harness shell layer.
#
# Source this file from zsh, then run:
#   xmux [-n <session>] [-- <codex args...>]

if [[ -n "$ZSH_VERSION" ]]; then
  _XMUX_SOURCED_DIR="${${(%):-%x}:A:h}"
else
  _XMUX_SOURCED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

_XMUX_SOURCE_INSTALL_DIR="$_XMUX_SOURCED_DIR"
if [[ "${_XMUX_SOURCE_INSTALL_DIR:t}" == "shell" && "${_XMUX_SOURCE_INSTALL_DIR:h:t}" == "runtime" ]]; then
  _XMUX_SOURCE_INSTALL_DIR="${_XMUX_SOURCE_INSTALL_DIR:h:h}"
fi

if [[ -n "${XMUX_INSTALL_DIR:-}" ]]; then
  XMUX_INSTALL_DIR="${XMUX_INSTALL_DIR:A}"
else
  XMUX_INSTALL_DIR="$_XMUX_SOURCE_INSTALL_DIR"
fi
export XMUX_INSTALL_DIR

if [[ -n "${XMUX_PROJECT_DIR:-}" ]]; then
  XMUX_PROJECT_DIR_EXPLICIT=1
  XMUX_PROJECT_DIR="${XMUX_PROJECT_DIR:A}"
else
  XMUX_PROJECT_DIR_EXPLICIT=0
fi

if [[ -n "${XMUX_STATE_DIR:-}" ]]; then
  XMUX_STATE_DIR_EXPLICIT=1
  XMUX_STATE_DIR="${XMUX_STATE_DIR:A}"
else
  XMUX_STATE_DIR_EXPLICIT=0
fi

XMUX_VERSION="2.0.2-beta.4"

_xmux_project_root() {
  local dir="${1:-$PWD}"
  dir="${dir:A}"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -e "$dir/.git" ]]; then
      print -r -- "$dir"
      return 0
    fi
    dir="${dir:h}"
  done
  print -r -- "${1:-$PWD}"
}

_xmux_refresh_paths() {
  if [[ "${XMUX_PROJECT_DIR_EXPLICIT:-0}" == "0" ]]; then
    XMUX_PROJECT_DIR="$(_xmux_project_root "$PWD")"
    export XMUX_PROJECT_DIR
  fi
  if [[ "${XMUX_STATE_DIR_EXPLICIT:-0}" == "0" ]]; then
    XMUX_STATE_DIR="$XMUX_PROJECT_DIR/.codex/xmux"
    export XMUX_STATE_DIR
  fi
  unset XMUX_DIR XMUX_HOME 2>/dev/null || true
}

_xmux_refresh_home() {
  _xmux_refresh_paths
}

_xmux_refresh_paths

_xmux_q() {
  printf '%q' "$1"
}

_xmux_print_version() {
  print -r -- "xmux $XMUX_VERSION"
}

_xmux_user_usage() {
  cat <<'EOF'
Usage:
  xmux -n <session> [--codex-bin <path>] [-- <codex args...>]
  xmux attach <session>
  xmux stop <session>
  xmux sessions
  xmux claude <args...>
  xmux codex <args...>
  xmux setup-xmux [--with-skills|--without-skills] [--refresh] [--dry-run] [--without-codex] [--without-claude]
  xmux cleanup-legacy [--dry-run] [--purge-archive] [--force]
  xmux doctor-xmux [--quiet|--json] [--without-codex] [--without-claude]
  xmux remove-xmux [--with-skills|--without-skills] [--dry-run] [--without-codex] [--without-claude]
  xmux --version
EOF
}

_xmux_require_tmux() {
  command -v tmux >/dev/null 2>&1 || {
    echo "error: tmux is required." >&2
    return 1
  }
}

_xmux_validate_session_name() {
  local name="$1"
  if [[ -z "$name" || "$name" == *:* ]]; then
    echo "error: invalid xmux session name '$name'." >&2
    return 1
  fi
}

_xmux_provider_brand_color() {
  case "$1" in
    codex) print -r -- "#10A37F" ;;
    claude) print -r -- "#D97757" ;;
    *) print -r -- "#10A37F" ;;
  esac
}

_xmux_status_color() {
  case "$1" in
    accent) _xmux_provider_brand_color codex ;;
    bg) print -r -- "#0E0F12" ;;
    surface) print -r -- "#15171C" ;;
    chip_bg) print -r -- "#252A31" ;;
    fg) print -r -- "#F5F7FA" ;;
    muted) print -r -- "#9EA1AA" ;;
    dim) print -r -- "#5C6068" ;;
    *) print -r -- "#F5F7FA" ;;
  esac
}

_xmux_status_label() {
  local label="$1"
  label="${label//[[:cntrl:]]/ }"
  label="${label//\#/##}"
  print -r -- "$label"
}

_xmux_current_tmux_session() {
  [[ -n "${TMUX_PANE:-}" ]] || return 1
  tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null
}

_xmux_apply_session_theme() {
  local session="$1" label="${2:-$1}"
  [[ -n "$session" ]] || return 0
  local accent bg surface chip_bg fg muted dim safe_label
  accent="$(_xmux_status_color accent)"
  bg="$(_xmux_status_color bg)"
  surface="$(_xmux_status_color surface)"
  chip_bg="$(_xmux_status_color chip_bg)"
  fg="$(_xmux_status_color fg)"
  muted="$(_xmux_status_color muted)"
  dim="$(_xmux_status_color dim)"
  safe_label="$(_xmux_status_label "$label")"

  tmux set-option -t "$session" status on 2>/dev/null || true
  tmux set-option -t "$session" status-position bottom 2>/dev/null || true
  tmux set-option -t "$session" status-style "bg=${bg},fg=${fg}" 2>/dev/null || true
  tmux set-option -t "$session" status-left-length 120 2>/dev/null || true
  tmux set-option -t "$session" status-right-length 45 2>/dev/null || true
  tmux set-option -t "$session" status-left "#[bg=${accent},fg=${bg},bold] XMux #[bg=${chip_bg},fg=${fg},nobold] ${safe_label} #[bg=${surface},fg=${muted}] #W " 2>/dev/null || true
  tmux set-option -t "$session" status-right "#[bg=${surface},fg=${muted}] xmux ${XMUX_VERSION} #[bg=${chip_bg},fg=${fg}] %H:%M " 2>/dev/null || true
  tmux set-option -t "$session" window-status-format "" 2>/dev/null || true
  tmux set-option -t "$session" window-status-current-format "" 2>/dev/null || true
  tmux set-option -t "$session" window-status-separator "" 2>/dev/null || true
  tmux set-option -t "$session" pane-border-style "fg=${surface}" 2>/dev/null || true
  tmux set-option -t "$session" pane-active-border-style "fg=${accent},bold" 2>/dev/null || true
  tmux set-option -t "$session" message-style "bg=${accent},fg=${bg},bold" 2>/dev/null || true
  tmux set-option -t "$session" message-command-style "bg=${chip_bg},fg=${fg}" 2>/dev/null || true
  tmux set-window-option -t "$session" mode-style "bg=${accent},fg=${bg}" 2>/dev/null || true
  tmux set-option -t "$session" @xmux-version "$XMUX_VERSION" 2>/dev/null || true
  tmux set-option -t "$session" @xmux-theme-accent "$accent" 2>/dev/null || true
  tmux set-option -t "$session" @xmux-theme-muted "$muted" 2>/dev/null || true
  tmux set-option -t "$session" @xmux-theme-dim "$dim" 2>/dev/null || true
}

_xmux_apply_pane_theme() {
  local pane="$1" provider="${2:-codex}" label="${3:-$provider}"
  [[ -n "$pane" ]] || return 0
  local accent codex_accent safe_label
  accent="$(_xmux_provider_brand_color "$provider")"
  codex_accent="$(_xmux_provider_brand_color codex)"
  safe_label="$(_xmux_status_label "$label")"
  tmux select-pane -t "$pane" -T "$safe_label" 2>/dev/null || true
  tmux set-option -pt "$pane" @xmux-provider "$provider" 2>/dev/null || true
  tmux set-option -pt "$pane" pane-border-style "fg=$(_xmux_status_color surface)" 2>/dev/null || true
  tmux set-option -pt "$pane" pane-active-border-style "fg=${codex_accent},bold" 2>/dev/null || true
  tmux set-option -pt "$pane" pane-border-format "#[fg=${accent},bold] #{pane_title} #[default]" 2>/dev/null || true
}

_xmux_harness_cli_path() {
  local kind="$1" candidate
  for candidate in \
      "$XMUX_INSTALL_DIR/dist/bin/xmux-${kind}-harness.js" \
      "$XMUX_INSTALL_DIR/src/${kind}/cli.js"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  return 1
}

_xmux_cmd_claude_harness() {
  local script
  script="$(_xmux_harness_cli_path claude)" || {
    echo "error: missing Claude harness CLI under $XMUX_INSTALL_DIR." >&2
    return 1
  }
  XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    node "$script" "$@"
}

_xmux_cmd_codex_harness() {
  local script
  script="$(_xmux_harness_cli_path codex)" || {
    echo "error: missing Codex harness CLI under $XMUX_INSTALL_DIR." >&2
    return 1
  }
  XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    node "$script" "$@"
}

_xmux_setup_script_path() {
  local candidate
  for candidate in \
      "$XMUX_INSTALL_DIR/dist/xmux/setup.js" \
      "$XMUX_INSTALL_DIR/src/xmux/setup.js"; do
    [[ -f "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  return 1
}

_xmux_run_setup_script() {
  local script
  script="$(_xmux_setup_script_path)" || {
    echo "error: missing XMux setup script under $XMUX_INSTALL_DIR." >&2
    return 1
  }
  XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" node "$script" --xmux-install-dir "$XMUX_INSTALL_DIR" "$@"
}

_xmux_cmd_setup_xmux() {
  _xmux_run_setup_script "$@"
}

_xmux_cmd_doctor_xmux() {
  _xmux_run_setup_script --doctor "$@"
}

_xmux_cmd_remove_xmux() {
  _xmux_run_setup_script --remove "$@"
}

_xmux_cmd_cleanup_legacy() {
  _xmux_run_setup_script --cleanup-legacy "$@"
}

_xmux_codex_home_env_name() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    print -r -- "CODEX_HOME"
  else
    print -r -- "CODEX_HOME"
  fi
}

_xmux_run_codex_lead() {
  local name="${XMUX_CODEX_SESSION_NAME:-default}"
  local codex_bin="${XMUX_CODEX_TUI_CMD:-codex}"
  local script tmux_session
  local -a args
  script="$(_xmux_harness_cli_path codex)" || {
    echo "[xmux] error: missing Codex pane harness." >&2
    return 1
  }
  if [[ -n "${TMUX_PANE:-}" ]]; then
    tmux_session="$(_xmux_current_tmux_session || true)"
    [[ -n "$tmux_session" ]] && _xmux_apply_session_theme "$tmux_session" "$tmux_session"
    tmux set-option -pt "$TMUX_PANE" @xmux-codex-session "$name" 2>/dev/null || true
    _xmux_apply_pane_theme "$TMUX_PANE" codex "codex:${name}"
  fi
  args=(pane-run --name "$name" --codex-cmd "$codex_bin")
  if [[ $# -gt 0 ]]; then
    args+=(-- "$@")
  fi
  env -u CODEX_HOME -u XMUX_DIR -u XMUX_HOME \
    XMUX_INSTALL_DIR="$XMUX_INSTALL_DIR" \
    XMUX_PROJECT_DIR="$XMUX_PROJECT_DIR" \
    XMUX_STATE_DIR="$XMUX_STATE_DIR" \
    XMUX_CODEX_SESSION_NAME="$name" \
    node "$script" "${args[@]}"
}

_xmux_build_codex_command() {
  local name="$1" codex_bin="$2"
  shift 2
  local wrapper cmd arg
  wrapper='source "$XMUX_INSTALL_DIR/runtime/shell/xmux.zsh"; _xmux_run_codex_lead "$@"'
  cmd="exec env -u CODEX_HOME -u XMUX_DIR -u XMUX_HOME XMUX_INSTALL_DIR=$(_xmux_q "$XMUX_INSTALL_DIR") XMUX_PROJECT_DIR=$(_xmux_q "$XMUX_PROJECT_DIR") XMUX_STATE_DIR=$(_xmux_q "$XMUX_STATE_DIR") XMUX_CODEX_SESSION_NAME=$(_xmux_q "$name") XMUX_CODEX_TUI_CMD=$(_xmux_q "$codex_bin") zsh -lc $(_xmux_q "$wrapper") xmux-lead"
  for arg in "$@"; do
    cmd+=" $(_xmux_q "$arg")"
  done
  print -r -- "$cmd"
}

_xmux_start() {
  _xmux_refresh_paths
  local session_name="" codex_bin="${XMUX_CODEX_TUI_CMD:-codex}" arg
  local -a codex_args
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -n|--name)
        [[ $# -ge 2 ]] || { echo "error: $arg requires a session name." >&2; return 1; }
        session_name="$2"
        shift 2
        ;;
      --codex-bin)
        [[ $# -ge 2 ]] || { echo "error: --codex-bin requires a path." >&2; return 1; }
        codex_bin="$2"
        shift 2
        ;;
      --claude|--gemini|--copilot|-T|--team|--with)
        echo "error: legacy teammate startup is removed. Start Codex with xmux, then use \$xmux-claude or /xmux-codex." >&2
        return 1
        ;;
      --)
        shift
        codex_args+=("$@")
        break
        ;;
      -h|--help)
        _xmux_user_usage
        return 0
        ;;
      *)
        codex_args+=("$arg")
        shift
        ;;
    esac
  done

  [[ -n "$session_name" ]] || session_name="$(basename "$XMUX_PROJECT_DIR")"
  _xmux_validate_session_name "$session_name" || return 1
  _xmux_require_tmux || return 1
  command -v "${codex_bin%% *}" >/dev/null 2>&1 || {
    echo "error: codex command not found: ${codex_bin%% *}" >&2
    return 1
  }

  if [[ -n "${TMUX:-}" && -t 0 && -t 1 ]]; then
    XMUX_CODEX_SESSION_NAME="$session_name" XMUX_CODEX_TUI_CMD="$codex_bin" _xmux_run_codex_lead "${codex_args[@]}"
    return $?
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "error: session '$session_name' already exists." >&2
    echo "       attach: xmux attach $session_name" >&2
    echo "       stop:   xmux stop $session_name" >&2
    echo "       new:    xmux -n <name>" >&2
    return 1
  fi

  local codex_cmd window_name
  codex_cmd="$(_xmux_build_codex_command "$session_name" "$codex_bin" "${codex_args[@]}")"
  window_name="$(basename "$XMUX_PROJECT_DIR")"
  tmux new-session -d -s "$session_name" -n "$window_name" -c "$XMUX_PROJECT_DIR" "$codex_cmd" || {
    echo "error: failed to create tmux session '$session_name'." >&2
    return 1
  }
  tmux set-option -t "$session_name" @xmux-managed 1 2>/dev/null || true
  tmux set-option -t "$session_name" @xmux-version "$XMUX_VERSION" 2>/dev/null || true
  tmux set-option -t "$session_name" @xmux-project-dir "$XMUX_PROJECT_DIR" 2>/dev/null || true
  _xmux_apply_session_theme "$session_name" "$session_name"

  if [[ -t 0 && -t 1 ]]; then
    tmux attach-session -t "$session_name"
  else
    echo "[xmux] session created session:$session_name detached:true"
  fi
}

_xmux_cmd_attach() {
  local session="${1:-}"
  [[ -n "$session" ]] || { echo "error: attach requires a session name." >&2; return 1; }
  _xmux_require_tmux || return 1
  _xmux_apply_session_theme "$session" "$session"
  tmux attach-session -t "$session"
}

_xmux_cmd_stop() {
  local session="${1:-}"
  [[ -n "$session" ]] || {
    echo "error: stop requires a session name." >&2
    echo "       usage: xmux stop <session>" >&2
    return 1
  }
  shift || true
  if [[ $# -gt 0 ]]; then
    echo "error: stop accepts only one session name." >&2
    echo "       usage: xmux stop <session>" >&2
    return 1
  fi
  _xmux_validate_session_name "$session" || return 1
  _xmux_require_tmux || return 1
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "error: session '$session' does not exist." >&2
    return 1
  fi
  if [[ "$(tmux show-option -qv -t "$session" @xmux-managed 2>/dev/null)" != "1" ]]; then
    echo "error: session '$session' is not owned by XMux." >&2
    echo "       use tmux directly: tmux kill-session -t $session" >&2
    return 1
  fi
  tmux kill-session -t "$session" || {
    echo "error: failed to stop session '$session'." >&2
    return 1
  }
  _xmux_cmd_codex_harness stop --name "$session" >/dev/null 2>&1 || true
  _xmux_cmd_claude_harness stop --name default >/dev/null 2>&1 || true
  echo "[xmux] stopped session '$session'"
}

_xmux_cmd_sessions() {
  _xmux_require_tmux || return 1
  tmux list-sessions -F '#S'
}

_xmux_legacy_removed() {
  echo "error: $1 was removed in XMux 2.x. Use the Codex-Claude hook harness through \$xmux-claude and /xmux-codex." >&2
  return 1
}

xmux-claude() {
  _xmux_legacy_removed "xmux-claude teammate command"
}

xmux-gemini() {
  _xmux_legacy_removed "xmux-gemini teammate command"
}

xmux-copilot() {
  _xmux_legacy_removed "xmux-copilot teammate command"
}

xmux() {
  _xmux_refresh_paths
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
    attach)
      shift
      _xmux_cmd_attach "$@"
      ;;
    stop)
      shift
      _xmux_cmd_stop "$@"
      ;;
    sessions)
      shift
      _xmux_cmd_sessions "$@"
      ;;
    claude)
      shift
      _xmux_cmd_claude_harness "$@"
      ;;
    codex|xmux-codex)
      shift
      _xmux_cmd_codex_harness "$@"
      ;;
    setup-xmux)
      shift
      _xmux_cmd_setup_xmux "$@"
      ;;
    doctor-xmux)
      shift
      _xmux_cmd_doctor_xmux "$@"
      ;;
    cleanup-legacy)
      shift
      _xmux_cmd_cleanup_legacy "$@"
      ;;
    remove-xmux)
      shift
      _xmux_cmd_remove_xmux "$@"
      ;;
    teamCreate|teammateAdd|teamStatus|teammateStatus|teammateShutdown|teamShutdown|teammates|bridgeStatus|ensure|recover|sendPane|shutdown|doctor|gemini|copilot|codex-worker)
      _xmux_legacy_removed "xmux $cmd"
      ;;
    help|-h|--help)
      _xmux_user_usage
      ;;
    *)
      echo "error: unknown xmux command '$cmd'." >&2
      _xmux_user_usage
      return 1
      ;;
  esac
}
