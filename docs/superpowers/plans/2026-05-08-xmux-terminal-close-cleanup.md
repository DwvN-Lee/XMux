# XMux Terminal Close Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make terminal close and explicit `xmux kill <name>` cleanly remove XMux-owned tmux sessions while archiving team state.

**Architecture:** Keep `xmux` and `xmux -n <name>` as the user-facing entrypoints. Reuse existing team member shutdown and archive primitives, add a clean-kill path that kills the owning tmux session before archiving active team state, and install a session-scoped tmux hook that triggers the same path when the last client detaches.

**Tech Stack:** zsh, tmux hooks/options, Python pytest, fake tmux shell scripts, isolated real tmux integration test.

---

## File Structure

- Modify `xmux.zsh`
  - Update duplicate-name errors to guide users to `xmux kill <display-name>`.
  - Reject user-facing `xmux attach`.
  - Disable `remain-on-exit` on XMux lead and teammate panes.
  - Add clean-kill helpers and the `xmux kill` command.
  - Install terminal-close cleanup hooks when recording the lead session.
  - Use clean kill after lead exit when running inside an XMux tmux session.

- Modify `tests/test_xmux_entrypoint.py`
  - Update existing duplicate-name and attach tests.
  - Add focused RED tests for `remain-on-exit`, `xmux kill`, cleanup hook installation, cleanup hook execution, and real terminal-close integration.

- Modify `README.md`
  - Replace user-facing `xmux attach` guidance with `xmux kill <name>` recovery guidance.

- Modify `share/zsh/site-functions/_xmux`
  - Add `kill` to debug/hidden command completion.
  - Keep `attach` absent from top-level user-facing completions.

---

### Task 1: Duplicate Name Guard And Attach Rejection

**Files:**
- Modify: `tests/test_xmux_entrypoint.py`
- Modify: `xmux.zsh`
- Modify: `README.md`

- [ ] **Step 1: Update the failing duplicate-name tests**

In `tests/test_xmux_entrypoint.py`, update `test_xmux_start_rejects_existing_active_display_name_when_detached` assertions:

```python
    assert result.returncode == 1
    assert (
        f"error: XMux name '{display_name}' is already active or attached."
        in result.stderr
    )
    assert "stale/zombie XMux session from a closed terminal" in result.stderr
    assert f"Run 'xmux kill {display_name}' to clean it" in result.stderr
    assert "then retry 'xmux -n dev'" in result.stderr
    assert "xmux attach" not in result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)
```

Update `test_xmux_start_rejects_existing_active_display_name_when_already_attached` assertions:

```python
    assert result.returncode == 1
    assert (
        f"error: XMux name '{display_name}' is already active or attached."
        in result.stderr
    )
    assert "stale/zombie XMux session from a closed terminal" in result.stderr
    assert f"Run 'xmux kill {display_name}' to clean it" in result.stderr
    assert "then retry 'xmux -n dev'" in result.stderr
    assert "xmux attach" not in result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("new-session ") for line in lines)
    assert not any(line.startswith("attach-session ") for line in lines)
```

Replace old attach success/reject tests with one user-facing rejection test. Delete the bodies of `test_xmux_attach_display_name_resolves_internal_session_when_detached`, `test_xmux_attach_display_name_rejects_when_already_attached`, `test_xmux_attach_display_name_rejects_ambiguous_active_team_matches`, and `test_xmux_attach_display_name_rejects_mixed_state_and_tmux_ambiguity`, then add this test near the old attach tests:

```python
def test_xmux_attach_command_is_rejected_for_user_flow(tmp_path):
    result = run_zsh(
        "xmux attach XMux/dev",
        {"XMUX_STATE_DIR": str(tmp_path / ".xmux")},
    )

    assert result.returncode == 1
    assert "error: xmux attach is not supported." in result.stderr
    assert "Use 'xmux -n dev' to start a fresh XMux session." in result.stderr
    assert "If an old session is stuck, run 'xmux kill XMux/dev' first." in result.stderr
```

- [ ] **Step 2: Run RED tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "existing_active_display_name or attach_command_is_rejected" -v
```

Expected:
- Duplicate tests fail because messages still mention `xmux attach`.
- Attach rejection test fails because `_xmux_cmd_attach` still resolves and attaches.

- [ ] **Step 3: Implement duplicate message and attach rejection**

In `xmux.zsh`, replace `_xmux_error_name_active` and `_xmux_error_name_attached` with shared recovery messaging:

```zsh
_xmux_retry_name_from_display() {
  local display_name="$1"
  if [[ "$display_name" == */* ]]; then
    print -r -- "${display_name#*/}"
  else
    print -r -- "$display_name"
  fi
}

_xmux_error_name_active() {
  local display_name="$1" retry_name
  retry_name="$(_xmux_retry_name_from_display "$display_name")"
  echo "error: XMux name '$display_name' is already active or attached." >&2
  echo "       This may be a stale/zombie XMux session from a closed terminal." >&2
  echo "       Run 'xmux kill $display_name' to clean it, then retry 'xmux -n $retry_name'." >&2
}

_xmux_error_name_attached() {
  _xmux_error_name_active "$1"
}
```

Replace `_xmux_cmd_attach` body with a user-facing rejection that still derives a useful retry name:

```zsh
_xmux_cmd_attach() {
  local target="${1:-}" retry_name
  retry_name="$(_xmux_retry_name_from_display "${target:-<name>}")"
  echo "error: xmux attach is not supported." >&2
  echo "       Use 'xmux -n $retry_name' to start a fresh XMux session." >&2
  if [[ -n "$target" ]]; then
    echo "       If an old session is stuck, run 'xmux kill $target' first." >&2
  else
    echo "       If an old session is stuck, run 'xmux kill <name>' first." >&2
  fi
  return 1
}
```

In `README.md`, replace the sentence:

```markdown
and `xmux attach XMux/refactor` for user-facing runtime operations.
```

with:

```markdown
and `xmux kill XMux/refactor` to clean stale or zombie XMux-owned sessions
before retrying `xmux -n refactor`.
```

- [ ] **Step 4: Run GREEN tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "existing_active_display_name or attach_command_is_rejected" -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add xmux.zsh README.md tests/test_xmux_entrypoint.py
git commit -m "Block XMux duplicate starts with kill guidance"
```

---

### Task 2: Disable `remain-on-exit` For XMux Panes

**Files:**
- Modify: `tests/test_xmux_entrypoint.py`
- Modify: `xmux.zsh`

- [ ] **Step 1: Write failing tests**

In `test_xmux_records_lead_pane_with_codex_brand_style`, add:

```python
    assert "set-option -p -t %1 remain-on-exit off" in lines
```

Add this test near `_xmux_spawn_member` or pane branding tests:

```python
def test_xmux_spawn_member_disables_remain_on_exit_for_teammate(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    xmux_mailbox.init_team("demo", "codex-lead", "codex", lead_pane="%1")

    claude = bin_dir / "claude"
    claude.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    claude.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  display-message)
    if [ "$2" = "#S" ] || [ "$2" = '#S' ]; then
      printf 'demo-session\\n'
    else
      printf '%%1\\n'
    fi
    ;;
  has-session)
    exit 0
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  split-window)
    printf '%%2\\n'
    ;;
  resize-pane|select-pane|set-option|run-shell)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux claude -t demo -s demo-session",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert "set-option -p -t %2 remain-on-exit off" in lines
```

- [ ] **Step 2: Run RED tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "records_lead_pane_with_codex_brand_style or spawn_member_disables_remain_on_exit" -v
```

Expected: FAIL because neither lead nor teammate pane sets `remain-on-exit off`.

- [ ] **Step 3: Implement pane option overrides**

In `_xmux_record_lead_pane`, after `@xmux-lead` is set, add:

```zsh
  tmux set-option -p -t "$pane" remain-on-exit off 2>/dev/null
```

In `_xmux_spawn_member`, after teammate pane metadata is set and before `_xmux_apply_pane_brand_style`, add:

```zsh
  tmux set-option -p -t "$agent_pane" remain-on-exit off 2>/dev/null
```

- [ ] **Step 4: Run GREEN tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "records_lead_pane_with_codex_brand_style or spawn_member_disables_remain_on_exit" -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add xmux.zsh tests/test_xmux_entrypoint.py
git commit -m "Disable remain-on-exit for XMux panes"
```

---

### Task 3: Manual `xmux kill <name>` Clean Kill

**Files:**
- Modify: `tests/test_xmux_entrypoint.py`
- Modify: `xmux.zsh`
- Modify: `share/zsh/site-functions/_xmux`

- [ ] **Step 1: Write failing manual clean-kill test**

Add this test near shutdown tests:

```python
def test_xmux_kill_display_name_archives_team_and_kills_owned_session(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    team = "XMux-dev-abc123"
    session = "xmux-XMux-dev-abc123"
    display_name = "XMux/dev"
    xmux_mailbox.init_team(team, "codex-lead", "codex", lead_pane="%1")
    xmux_mailbox.register_member(team, "worker-a", "gemini", pane="%2")

    team_dir = state_dir / "teams" / team
    cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    cfg["display_name"] = display_name
    cfg["lead"]["session"] = session
    cfg["lead"]["display_name"] = display_name
    cfg["members"]["codex-lead"]["session"] = session
    (team_dir / "team.json").write_text(
        json.dumps(cfg, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-sessions)
    if [ "$1" = "-F" ] && [ "$2" = "#S" ]; then
      printf '%s\\n' "$TMUX_FAKE_SESSION"
    else
      printf '%s\\t0\\n' "$TMUX_FAKE_SESSION"
    fi
    ;;
  has-session)
    [ "$2" = "$TMUX_FAKE_SESSION" ]
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_TEAM"
    elif [ "$4" = '@xmux-display-name' ]; then
      printf '%s\\n' "$TMUX_FAKE_DISPLAY"
    fi
    ;;
  list-panes)
    printf '%%2\\n'
    ;;
  display-message)
    target=""
    fmt=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        -p)
          fmt="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ "$target" = "%2" ] && [ "$fmt" = '#{@xmux-team}\t#{@xmux-agent}' ]; then
      printf '%s\\tworker-a\\n' "$TMUX_FAKE_TEAM"
    elif [ "$target" = "%1" ] && [ "$fmt" = '#{@xmux-team}\t#{@xmux-lead}' ]; then
      printf '%s\\t1\\n' "$TMUX_FAKE_TEAM"
    fi
    ;;
  send-keys|kill-pane|set-option)
    ;;
  kill-session)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        f"xmux kill {display_name}",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION": session,
            "TMUX_FAKE_TEAM": team,
            "TMUX_FAKE_DISPLAY": display_name,
        },
    )

    assert result.returncode == 0, result.stderr
    assert not team_dir.exists()
    archives = sorted((state_dir / "archive").glob(f"*-{team}"))
    assert len(archives) == 1
    archive = archives[0]
    archive_meta = json.loads((archive / "archive.json").read_text(encoding="utf-8"))
    assert archive_meta["reason"] == "manual-kill"
    team_cfg = json.loads((archive / "team.json").read_text(encoding="utf-8"))
    assert team_cfg["status"] == "archived"
    assert team_cfg["members"]["worker-a"]["active"] is False
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert f"kill-session -t {session}" in lines
    assert "kill-pane -t %2" in lines
    assert f"[xmux] kill complete name:{display_name} team:{team}" in result.stdout
```

- [ ] **Step 2: Write failing kill safety tests**

Add:

```python
def test_xmux_kill_refuses_non_xmux_owned_session(tmp_path):
    state_dir = tmp_path / ".xmux"
    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    exit 0
    ;;
  show-option)
    ;;
  kill-session)
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        "xmux kill raw-session",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 1
    assert "is not an XMux-owned session" in result.stderr
    assert "kill-session" not in log_path.read_text(encoding="utf-8")
```

Add:

```python
def test_xmux_kill_handles_missing_tmux_session_but_archives_owned_team(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    team = "XMux-dev-abc123"
    session = "xmux-XMux-dev-abc123"
    display_name = "XMux/dev"
    xmux_mailbox.init_team(team, "codex-lead", "codex", lead_pane="%1")
    team_dir = state_dir / "teams" / team
    cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    cfg["display_name"] = display_name
    cfg["lead"]["session"] = session
    cfg["lead"]["display_name"] = display_name
    (team_dir / "team.json").write_text(
        json.dumps(cfg, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-sessions)
    exit 0
    ;;
  has-session)
    exit 1
    ;;
  kill-session)
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        f"xmux kill {display_name}",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
        },
    )

    assert result.returncode == 0, result.stderr
    assert not team_dir.exists()
    archives = sorted((state_dir / "archive").glob(f"*-{team}"))
    assert len(archives) == 1
    archive_meta = json.loads((archives[0] / "archive.json").read_text(encoding="utf-8"))
    assert archive_meta["reason"] == "manual-kill"
    assert "kill-session" not in log_path.read_text(encoding="utf-8")
```

- [ ] **Step 3: Run RED tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "xmux_kill" -v
```

Expected: FAIL because `xmux kill` is an unknown command.

- [ ] **Step 4: Implement kill resolution and clean kill**

In `xmux.zsh`, add these helpers after `_xmux_cmd_shutdown`:

```zsh
_xmux_active_team_display_name() {
  local team="$1"
  _xmux_display_name_for_team "$team" 2>/dev/null || print -r -- "$team"
}

_xmux_session_belongs_to_team() {
  local session="$1" team="$2"
  [[ -n "$session" && -n "$team" ]] || return 1
  tmux has-session -t "$session" 2>/dev/null || return 1
  [[ "$(tmux show-option -v -t "$session" @xmux-team 2>/dev/null)" == "$team" ]]
}

_xmux_resolve_kill_target() {
  local target="$1"
  local team="" session="" display="" owner=""
  [[ -n "$target" ]] || { echo "error: target is required for xmux kill." >&2; return 1; }

  if [[ "$target" == */* ]]; then
    team="$(_xmux_team_for_display_name "$target")" || return $?
    display="$target"
    session="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" session 2>/dev/null || true)"
    [[ -z "$session" || "$session" == "-" ]] && session="$(_xmux_session_for_team "$team" 2>/dev/null || true)"
  elif [[ -d "$(_xmux_team_dir "$target")" ]] && _xmux_team_is_active "$target"; then
    team="$target"
    display="$(_xmux_active_team_display_name "$team")"
    session="$(_xmux_member_field "$team" "$XMUX_LEAD_AGENT" session 2>/dev/null || true)"
    [[ -z "$session" || "$session" == "-" ]] && session="$(_xmux_session_for_team "$team" 2>/dev/null || true)"
  elif tmux has-session -t "$target" 2>/dev/null; then
    owner="$(tmux show-option -v -t "$target" @xmux-team 2>/dev/null || true)"
    [[ -n "$owner" ]] || {
      echo "error: '$target' is not an XMux-owned session." >&2
      return 1
    }
    _xmux_team_is_active "$owner" || {
      echo "error: XMux team '$owner' is not active." >&2
      return 1
    }
    team="$owner"
    session="$target"
    display="$(_xmux_active_team_display_name "$team")"
  else
    echo "error: XMux kill target '$target' was not found." >&2
    return 1
  fi

  print -r -- "$team"$'\t'"$session"$'\t'"$display"
}

_xmux_clean_kill_team() {
  local team="$1" session="$2" reason="$3" display_name="$4"
  local team_dir row_team name role provider active pane member_session mode updated
  local -a failed_agents=()
  team_dir="$(_xmux_team_dir "$team")"
  [[ -f "$team_dir/team.json" ]] || { echo "error: XMux team '$team' does not exist at $team_dir." >&2; return 1; }

  _xmux_mark_team_shutdown_start "$team" "$reason" || return 1
  while IFS=$'\t' read -r row_team name role provider active pane member_session mode updated; do
    [[ -z "$name" || "$role" == "lead" ]] && continue
    _xmux_shutdown_teammate "$team" "$name" "$provider" "$pane" 5 || failed_agents+=("$name")
  done < <(_xmux_emit_team_members "$team")

  if (( ${#failed_agents[@]} > 0 )); then
    local failed_csv failed_text
    failed_csv="${(j:,:)failed_agents}"
    failed_text="${(j:, :)failed_agents}"
    _xmux_mark_team_shutdown_degraded "$team" "$reason" "$failed_csv" || true
    echo "error: kill incomplete for team:$team; failed agents: $failed_text" >&2
    echo "       Team state was not archived. Requests and inbox history remain at $team_dir." >&2
    return 1
  fi

  if [[ -n "$session" && "$session" != "-" ]] && tmux has-session -t "$session" 2>/dev/null; then
    if ! _xmux_session_belongs_to_team "$session" "$team"; then
      echo "error: refusing to kill session '$session' because it is not owned by XMux team '$team'." >&2
      return 1
    fi
    tmux kill-session -t "$session" || return 1
  fi

  local archive_dir
  archive_dir="$(_xmux_archive_team_dir "$team" "$reason")" || return 1
  echo "[xmux] kill complete name:$display_name team:$team archived:$archive_dir reason:$reason"
}

_xmux_cmd_kill() {
  local reason="manual-kill" target="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --reason)
        [[ $# -ge 2 ]] || { echo "error: --reason requires a reason." >&2; return 1; }
        reason="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: xmux kill <display-name|team|session> [--reason <reason>]"
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
  local record team session display_name
  record="$(_xmux_resolve_kill_target "$target")" || return $?
  IFS=$'\t' read -r team session display_name <<< "$record"
  _xmux_clean_kill_team "$team" "$session" "$reason" "$display_name"
}
```

In the main `xmux()` command dispatcher, add:

```zsh
    kill)
      shift
      _xmux_cmd_kill "$@"
      ;;
```

In `share/zsh/site-functions/_xmux`, add `kill` to the debug command case:

```zsh
  teammateStatus|teammateShutdown|teamShutdown|teamStatus|teammates|ensure|doctor|bridgeStatus|recover|shutdown|kill)
```

- [ ] **Step 5: Run GREEN tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "xmux_kill" -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add xmux.zsh share/zsh/site-functions/_xmux tests/test_xmux_entrypoint.py
git commit -m "Add XMux clean kill command"
```

---

### Task 4: Terminal-Close Hook And Lead-Exit Session Kill

**Files:**
- Modify: `tests/test_xmux_entrypoint.py`
- Modify: `xmux.zsh`

Before Step 5 writes production code, complete Task 5 Steps 1 and 2 as an
integration RED check. Task 5 is separated for readability, but its RED test is
part of the terminal-close implementation cycle.

- [ ] **Step 1: Write failing hook installation test**

Add:

```python
def test_xmux_start_installs_terminal_close_cleanup_hook(tmp_path):
    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "tmux.log"
    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )

    codex = bin_dir / "codex"
    codex.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    codex.chmod(0o755)

    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  has-session)
    exit 1
    ;;
  new-session)
    ;;
  list-panes)
    printf '%%1\\n'
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_TEAM"
    fi
    ;;
  set-option|set-window-option|select-pane|set-hook)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_xmux_bin(
        ["-n", "dev"],
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX": None,
            "TMUX_PANE": None,
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_TEAM": team_name,
        },
        cwd=project,
    )

    assert result.returncode == 0, result.stderr
    lines = log_path.read_text(encoding="utf-8").splitlines()
    hook_line = next(line for line in lines if line.startswith(f"set-hook -t {session_name} client-detached "))
    assert "#{==:#{session_attached},0}" in hook_line
    assert "xmux kill" in hook_line
    assert "--reason terminal-close" in hook_line
    assert display_name in hook_line
```

- [ ] **Step 2: Write failing hook execution test**

Add:

```python
def test_xmux_terminal_close_cleanup_archives_team_and_kills_session(tmp_path, monkeypatch):
    state_dir = tmp_path / ".xmux"
    monkeypatch.setenv("XMUX_STATE_DIR", str(state_dir))
    team = "XMux-dev-abc123"
    session = "xmux-XMux-dev-abc123"
    display_name = "XMux/dev"
    xmux_mailbox.init_team(team, "codex-lead", "codex", lead_pane="%1")
    team_dir = state_dir / "teams" / team
    cfg = json.loads((team_dir / "team.json").read_text(encoding="utf-8"))
    cfg["display_name"] = display_name
    cfg["lead"]["session"] = session
    cfg["lead"]["display_name"] = display_name
    (team_dir / "team.json").write_text(
        json.dumps(cfg, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    log_path = tmp_path / "tmux.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-sessions)
    if [ "$1" = "-F" ] && [ "$2" = "#S" ]; then
      printf '%s\\n' "$TMUX_FAKE_SESSION"
    else
      printf '%s\\t0\\n' "$TMUX_FAKE_SESSION"
    fi
    ;;
  has-session)
    [ "$2" = "$TMUX_FAKE_SESSION" ]
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf '%s\\n' "$TMUX_FAKE_TEAM"
    elif [ "$4" = '@xmux-display-name' ]; then
      printf '%s\\n' "$TMUX_FAKE_DISPLAY"
    fi
    ;;
  kill-session)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)

    result = run_zsh(
        f"_xmux_cmd_kill --reason terminal-close {display_name}",
        {
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "TMUX_FAKE_LOG": str(log_path),
            "TMUX_FAKE_SESSION": session,
            "TMUX_FAKE_TEAM": team,
            "TMUX_FAKE_DISPLAY": display_name,
        },
    )

    assert result.returncode == 0, result.stderr
    assert not team_dir.exists()
    archives = sorted((state_dir / "archive").glob(f"*-{team}"))
    assert len(archives) == 1
    archive_meta = json.loads((archives[0] / "archive.json").read_text(encoding="utf-8"))
    assert archive_meta["reason"] == "terminal-close"
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert f"kill-session -t {session}" in lines
```

- [ ] **Step 3: Write failing lead-exit clean-kill test**

Update `test_xmux_lead_wrapper_shutdown_preserves_codex_exit_status` by adding a fake `tmux` and `XMUX_LEAD_SESSION` to assert clean kill happens only when session metadata is available:

```python
    log_path = tmp_path / "tmux.log"
    tmux = bin_dir / "tmux"
    tmux.write_text(
        """#!/bin/sh
printf '%s\\n' "$*" >> "$TMUX_FAKE_LOG"
cmd="$1"
shift
case "$cmd" in
  list-sessions)
    printf 'demo-session\\t0\\n'
    ;;
  has-session)
    [ "$2" = "demo-session" ]
    ;;
  show-option)
    if [ "$4" = '@xmux-team' ]; then
      printf 'demo\\n'
    fi
    ;;
  kill-session)
    ;;
esac
""",
        encoding="utf-8",
    )
    tmux.chmod(0o755)
```

Add to `env`:

```python
        "XMUX_LEAD_SESSION": "demo-session",
        "TMUX_FAKE_LOG": str(log_path),
```

After archive assertions, add:

```python
    assert "kill-session -t demo-session" in log_path.read_text(encoding="utf-8")
```

- [ ] **Step 4: Run RED tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "terminal_close_cleanup or terminal_close_cleanup_hook or lead_wrapper_shutdown_preserves" -v
```

Expected:
- Hook installation test fails because no `client-detached` hook is installed.
- Hook cleanup test passes only after Task 3 exists; if it fails, failure should point to missing `terminal-close` reason path.
- Lead-exit assertion fails because `_xmux_run_codex_lead` does not kill the session.

- [ ] **Step 5: Implement terminal-close hook installation**

In `xmux.zsh`, add:

```zsh
_xmux_install_terminal_close_cleanup_hook() {
  local team="$1" session="$2" display_name="$3"
  local env_prefix hook_cmd kill_cmd
  [[ -n "$team" && -n "$session" && -n "$display_name" ]] || return 0
  env_prefix="$(_xmux_runtime_env_assignments)"
  kill_cmd="env -u XMUX_DIR -u XMUX_HOME $env_prefix xmux kill --reason terminal-close $(_xmux_q "$display_name")"
  hook_cmd="if-shell -F '#{==:#{session_attached},0}' 'run-shell -b $(_xmux_q "sleep 0.2; $kill_cmd")'"
  tmux set-hook -t "$session" client-detached "$hook_cmd" 2>/dev/null || true
}
```

In `_xmux_record_lead_pane`, after `_xmux_apply_session_brand_status`, add:

```zsh
  _xmux_install_terminal_close_cleanup_hook "$team" "$session" "$display_name"
```

- [ ] **Step 6: Implement lead-exit clean kill**

In `_xmux_build_codex_env_command`, include the lead session:

```zsh
XMUX_LEAD_SESSION=$(_xmux_q "$session_name")
```

The function currently does not receive `session_name`; update its signature to:

```zsh
_xmux_build_codex_env_command() {
  local team_name="$1" team_dir="$2" lead_session="$3"
  shift 3
```

Update its call site in `_xmux_start`:

```zsh
  codex_cmd="$(_xmux_build_codex_env_command "$team_name" "$team_dir" "$session_name" "$shutdown_on_lead_exit" -- "${codex_args[@]}")"
```

In the existing-tmux branch of `_xmux_start`, add `XMUX_LEAD_SESSION="$session"` to the direct lead environment:

```zsh
    XMUX_TEAM="$team_name" \
      XMUX_AGENT="$XMUX_LEAD_AGENT" \
      XMUX_TEAM_DIR="$team_dir" \
      XMUX_LEAD_SESSION="$session" \
      XMUX_SHUTDOWN_ON_LEAD_EXIT="$shutdown_on_lead_exit" \
      _xmux_with_terminal_codex_theme _xmux_run_codex_lead "${codex_args[@]}"
```

In `_xmux_run_codex_lead`, replace the automatic shutdown block with:

```zsh
  if _xmux_shutdown_on_lead_exit_enabled "${XMUX_SHUTDOWN_ON_LEAD_EXIT:-1}" && [[ -n "${XMUX_TEAM:-}" ]]; then
    if (( lead_stdio_ready )); then
      if [[ -n "${XMUX_LEAD_SESSION:-}" ]]; then
        xmux kill --reason lead-exit "$XMUX_TEAM" || {
          echo "[xmux] warning: automatic kill failed for team:$XMUX_TEAM" >&2
        }
      else
        xmux shutdown -t "$XMUX_TEAM" --reason lead-exit --lead-already-exiting || {
          echo "[xmux] warning: automatic shutdown failed for team:$XMUX_TEAM" >&2
        }
      fi
    else
      echo "[xmux] warning: skipping automatic shutdown for team:$XMUX_TEAM because the lead did not start with terminal stdio." >&2
    fi
  fi
```

Keep the fallback branch so existing non-tmux unit tests and scripted runs without session metadata still preserve the current behavior.

- [ ] **Step 7: Run GREEN tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "terminal_close_cleanup or terminal_close_cleanup_hook or lead_wrapper_shutdown_preserves" -v
```

Expected: PASS.

- [ ] **Step 8: Commit**

Run:

```bash
git add xmux.zsh tests/test_xmux_entrypoint.py
git commit -m "Clean XMux sessions on terminal close"
```

---

### Task 5: Real Tmux Terminal-Close Integration

**Files:**
- Modify: `tests/test_xmux_entrypoint.py`

Run this task through Step 2 before Task 4 Step 5. After Task 4 is green, return
to Step 4 here to verify the final integration criterion.

- [ ] **Step 1: Add polling helper and integration test**

Add this helper near other test helpers:

```python
def wait_until(predicate, timeout=5.0, interval=0.1):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = predicate()
        if last:
            return True
        time.sleep(interval)
    return False
```

Add this integration test near lead wrapper tests:

```python
def test_xmux_terminal_close_real_tmux_kills_session_and_archives_team(tmp_path):
    tmux = shutil.which("tmux")
    if tmux is None:
        pytest.skip("tmux is not installed")

    project = tmp_path / "XMux"
    project.mkdir()
    (project / ".git").mkdir()
    state_dir = project / ".codex" / "xmux"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    socket_name = f"xmux-test-{os.getpid()}-{int(time.time() * 1000)}"

    codex = bin_dir / "codex"
    codex.write_text(
        "#!/bin/sh\n"
        "trap 'exit 0' TERM INT HUP\n"
        "while :; do sleep 1; done\n",
        encoding="utf-8",
    )
    codex.chmod(0o755)

    tmux_wrapper = bin_dir / "tmux"
    tmux_wrapper.write_text(
        f"#!/bin/sh\nexec {tmux} -L {socket_name} -f /dev/null \"$@\"\n",
        encoding="utf-8",
    )
    tmux_wrapper.chmod(0o755)

    display_name, team_name, session_name = _resolve_scoped_name_fields(
        project, state_dir, "dev"
    )

    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(
        [str(ROOT / "bin" / "xmux"), "-n", "dev"],
        cwd=project,
        env={
            **os.environ,
            "XMUX_STATE_DIR": str(state_dir),
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "XMUX_TERMINAL_THEME": "0",
        },
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        text=False,
        close_fds=True,
    )
    os.close(slave_fd)

    try:
        assert wait_until(
            lambda: subprocess.run(
                [tmux, "-L", socket_name, "-f", "/dev/null", "has-session", "-t", session_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            ).returncode == 0,
            timeout=5,
        )
        os.close(master_fd)
        master_fd = None

        assert wait_until(
            lambda: subprocess.run(
                [tmux, "-L", socket_name, "-f", "/dev/null", "has-session", "-t", session_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            ).returncode != 0,
            timeout=8,
        )
        assert not (state_dir / "teams" / team_name).exists()
        archives = sorted((state_dir / "archive").glob(f"*-{team_name}"))
        assert len(archives) == 1
        archive_meta = json.loads((archives[0] / "archive.json").read_text(encoding="utf-8"))
        assert archive_meta["reason"] == "terminal-close"
        team_cfg = json.loads((archives[0] / "team.json").read_text(encoding="utf-8"))
        assert team_cfg["display_name"] == display_name
        assert team_cfg["status"] == "archived"
    finally:
        if master_fd is not None:
            os.close(master_fd)
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        subprocess.run(
            [tmux, "-L", socket_name, "-f", "/dev/null", "kill-server"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
```

At the top of `tests/test_xmux_entrypoint.py`, add:

```python
import pty
import pytest
```

- [ ] **Step 2: Run RED integration test**

Run:

```bash
pytest tests/test_xmux_entrypoint.py::test_xmux_terminal_close_real_tmux_kills_session_and_archives_team -v
```

Expected before Task 4 Step 5 implementation: FAIL because closing the PTY
leaves the session behind or does not archive with `terminal-close`.

- [ ] **Step 3: Keep integration fixes scoped to the failing assertion**

The hook implementation from Task 4 already uses `_xmux_runtime_env_assignments`
and a `sleep 0.2` delay in the `run-shell` command. If this RED test exposes a
different defect, change only the smallest code path named by the failing
assertion and rerun this single test before broadening verification.

- [ ] **Step 4: Run GREEN integration test**

Run:

```bash
pytest tests/test_xmux_entrypoint.py::test_xmux_terminal_close_real_tmux_kills_session_and_archives_team -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add xmux.zsh tests/test_xmux_entrypoint.py
git commit -m "Verify XMux cleanup on terminal close"
```

---

### Task 6: Full Regression Verification

**Files:**
- Modify only if tests expose a regression.

- [ ] **Step 1: Run targeted feature tests**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -k "kill or terminal_close or remain_on_exit or existing_active_display_name or attach_command" -v
```

Expected: PASS.

- [ ] **Step 2: Run full entrypoint suite**

Run:

```bash
pytest tests/test_xmux_entrypoint.py -v
```

Expected: PASS.

- [ ] **Step 3: Run repository test suite**

Run:

```bash
pytest -v
```

Expected: PASS.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat HEAD
git diff HEAD -- xmux.zsh tests/test_xmux_entrypoint.py README.md share/zsh/site-functions/_xmux
```

Expected:
- No `xmux attach` recovery guidance remains in user-facing README or duplicate errors.
- `xmux kill` is implemented and completion-aware.
- Terminal-close hook calls the clean-kill path.
- Active team state is archived, not deleted without history.

- [ ] **Step 5: Final commit if regression fixes were needed**

If Step 2 or Step 3 required additional fixes, commit those fixes:

```bash
git add xmux.zsh tests/test_xmux_entrypoint.py README.md share/zsh/site-functions/_xmux
git commit -m "Stabilize XMux terminal cleanup"
```

If no files changed after the previous task commits, do not create an empty commit.
