# XMux Terminal Close Cleanup Design

## Goal

XMux must cleanly terminate the XMux runtime when the terminal hosting the
attached XMux session is closed. The final green condition is that terminal
closure removes the XMux tmux session, shuts down teammates and helpers through
the normal shutdown path, archives team state, and leaves no active
`teams/<team>` directory behind.

## Decisions

- `xmux` and `xmux -n <name>` are the single source of truth for user-facing
  session entry.
- `xmux attach` is not a supported user-facing entry path. It should fail with
  guidance to use `xmux` or `xmux -n <name>`.
- If a same-name XMux session already exists, `xmux -n <name>` must not attach
  to it or kill it automatically.
- The duplicate-name error should warn that the existing session may be stale
  or zombie state from a closed terminal, then tell the user to run
  `xmux kill <display-name>` and retry `xmux -n <name>`.
- `xmux kill <display-name>` performs a clean kill: teammate/helper shutdown,
  tmux session kill, team archive, and active team directory removal.
- `xmux kill` only targets XMux-owned sessions by default. Raw non-XMux tmux
  sessions must be refused.
- If XMux state exists but the tmux session is already gone, `xmux kill` still
  archives the team state and clears the active team directory.
- XMux-managed lead and teammate panes must set `remain-on-exit off` so user
  global tmux configuration cannot leave dead panes behind after process exit.

## Architecture

The implementation must reuse the existing team shutdown and archive model
rather than adding a long-running supervisor. The lifecycle should be expressed
as explicit shell helpers in `xmux.zsh`:

- A duplicate guard for `xmux` and `xmux -n <name>`.
- A `kill` command that resolves display name, team name, or owned session to a
  team/session pair.
- A clean-kill helper shared by manual `xmux kill` and terminal-close cleanup.
- A session-scoped tmux hook installed when XMux creates or records the lead
  session.

The terminal-close hook must guard on the session having zero attached clients.
The hook should call back into `xmux kill` or the shared clean-kill helper with
a `terminal-close` reason only after that condition is true. This keeps
terminal-close cleanup behavior aligned with the manual cleanup path and avoids
separate cleanup semantics.

## Data Flow

1. User runs `xmux` or `xmux -n dev`.
2. XMux resolves the display name, internal team name, and internal tmux session.
3. If the resolved name already has an active XMux-owned session or active team
   state, XMux fails and prints the `xmux kill <display-name>` recovery message.
4. On new session creation, XMux records lead pane metadata, disables
   `remain-on-exit`, installs terminal-close cleanup hook metadata, and starts
   Codex.
5. If Codex exits normally, the lead wrapper performs automatic team shutdown
   and then removes the owning tmux session.
6. If the terminal closes and tmux detaches the last client, the session hook
   confirms the session has zero attached clients and runs the same clean-kill
   path with reason `terminal-close`.
7. Manual `xmux kill XMux/dev` resolves the team/session, verifies ownership,
   shuts down teammates and helpers, kills the tmux session when present or
   confirms it is already gone, and then moves `teams/<team>` into
   `archive/<timestamp>-<team>`.

## Error Handling

- Duplicate start errors must avoid suggesting `xmux attach`.
- `xmux kill` must fail without killing anything if the target resolves only to
  a non-XMux tmux session.
- `xmux kill` must treat an already-missing tmux session as acceptable when
  active XMux team state still exists and can be archived.
- Cleanup must be idempotent enough for lead-exit and terminal-close paths to
  race. A second cleanup attempt should either no-op or report that the active
  team no longer exists without killing unrelated tmux sessions.
- If teammate/helper shutdown fails, the team should not be archived. The
  degraded team state should remain active enough for diagnosis.

## Testing Plan

Tests are written feature by feature. Each test must be observed failing for
the expected reason before implementation for that feature begins.

1. Duplicate guard:
   `test_xmux_start_blocks_existing_name_and_suggests_kill`
   verifies that a same-name XMux session blocks `xmux -n dev`, does not attach
   or create, and prints `xmux kill XMux/dev` plus retry guidance.

2. Attach rejection:
   `test_xmux_attach_command_is_rejected_for_user_flow`
   verifies that user-facing `xmux attach XMux/dev` fails and points to
   `xmux -n dev` or `xmux kill XMux/dev`.

3. Zombie pane prevention:
   `test_xmux_record_lead_pane_disables_remain_on_exit` and
   `test_xmux_spawn_member_disables_remain_on_exit_for_teammate`
   verify pane-scoped `remain-on-exit off` for lead and teammate panes.

4. Manual clean kill:
   `test_xmux_kill_display_name_archives_team_and_kills_owned_session`
   verifies teammate shutdown, `tmux kill-session`, archive creation, archived
   metadata, and removal of active `teams/<team>`.

5. Kill safety:
   `test_xmux_kill_refuses_non_xmux_owned_session` verifies raw tmux sessions
   are not killed.
   `test_xmux_kill_handles_missing_tmux_session_but_archives_owned_team`
   verifies active state is archived when tmux session is already gone.

6. Terminal-close hook installation:
   `test_xmux_start_installs_terminal_close_cleanup_hook`
   verifies session-scoped cleanup hook installation during XMux startup.

7. Terminal-close cleanup path:
   `test_xmux_terminal_close_cleanup_archives_team_and_kills_session`
   invokes the hook command path with fake tmux and verifies it matches manual
   clean-kill behavior.

8. Final integration:
   `test_xmux_terminal_close_real_tmux_kills_session_and_archives_team`
   uses an isolated real tmux server and fake Codex process to verify terminal
   closure removes the tmux session, removes active team state, and creates one
   archive with reason `terminal-close`.

Targeted verification command:

```bash
pytest tests/test_xmux_entrypoint.py -k "kill or terminal_close or remain_on_exit or existing_name or attach_command" -v
```

Final verification command:

```bash
pytest tests/test_xmux_entrypoint.py -v
```
