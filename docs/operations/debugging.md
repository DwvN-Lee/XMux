Back to [README](../../README.md)

# XMux Debugging

XMux operation is wrapper-first. Use `xmux` wrappers and XMux MCP/mailbox tools for normal diagnosis, recovery, and communication checks. Raw `tmux` commands are an implementation-level escape hatch only when a wrapper cannot answer the question.

## Default Path

Run wrappers through the executable XMux entrypoint. For Codex automation,
prefer `xmux <subcommand>` from the Codex shell policy PATH installed by
`xmux setup-codex`.
If that wrapper is unavailable, use `$XMUX_INSTALL_DIR/bin/xmux` so execution
can be scoped to XMux commands instead of arbitrary interactive shell text.

```zsh
xmux teamStatus -t <team>
```

If a sandboxed Codex command returns no output or `xmux` is not found, do not
interpret that as an empty XMux runtime. Rerun the same scoped command through
an explicit XMux executable path before falling back to interactive zsh. In a
Codex skill context, rely on `xmux` from shell policy PATH or
`$XMUX_INSTALL_DIR/bin/xmux`; do not derive a checkout-relative executable
path. Check Codex integration with `xmux doctor-codex`; repair it with
`xmux setup-codex`; remove only XMux-managed Codex state with
`xmux remove-codex`. If the explicit executable is blocked by the Codex command sandbox,
request approval for the exact XMux executable prefix instead of switching to
`zsh -ic` as a broad bypass. Run it from the target project cwd, or set
`XMUX_PROJECT_DIR` or `XMUX_STATE_DIR`, so project-local team state resolves
correctly.

Useful read-only checks:

```zsh
xmux help debug
xmux sessions
xmux teamStatus -t <team>
xmux doctor -t <team>
xmux teammateStatus -t <team>
xmux paneInfo <agent> -t <team>
node dist/bin/xmux-mailbox.js team-status <team>
```

When tmux socket access is unavailable, read-only wrappers should still report
file-backed team state where possible and mark pane liveness as `unknown`
instead of treating panes as dead.

For lead-to-teammate communication checks, use XMux MCP or mailbox request tracking:

- `team_status`
- `send_to_teammate`
- `wait_teammate_response`
- `read_teammate_response`
- `dist/bin/xmux-mailbox.js enqueue-request`
- `dist/bin/xmux-mailbox.js wait-response`

Do not paste prompts directly into teammate panes for normal communication checks. Direct pane input bypasses request ids and can produce false positives.

## Recovery

If a teammate pane is live but its relay is dead, restart only the bridge:

```zsh
xmux recover -t <team> <agent> --restart-bridge
```

If the provider CLI is dead, stale, or needs to reload MCP config, restart the teammate:

```zsh
xmux recover -t <team> <agent> --restart-teammate --session <session>
```

If a wrapper is running outside an XMux tmux context and cannot infer the session, pass the session explicitly:

```zsh
xmux teammateAdd -t <team> --session <session> claude gemini copilot
```

`xmux doctor` and `xmux teammateStatus` are read-only. `xmux recover`,
`xmux teammateShutdown`, and `xmux teamShutdown` mutate runtime state and
should always be scoped explicitly.

## Shutdown

Use `xmux teammateShutdown -t <team> <agent>` for one teammate. It should keep
the user on the current pane or the Codex lead pane while it terminates that
teammate pane and helper processes, and it does not archive the team.

Use `xmux teamShutdown -t <team>` for the whole team lifecycle. It leaves the lead
pane alone, stops non-lead teammates, cleans bridge and Copilot HTTP MCP pid
files, preserves `team.json`, inboxes, requests, request ids, and
`events.jsonl`, then archives the team under
`.codex/xmux/archive/<timestamp>-<team>`. Codex lead `/exit` naturally exits the
Codex process, and the XMux wrapper runs the same shutdown/archive path by
default. Start with `--keep-team-on-lead-exit` when live panes should remain
available for debugging.

## Copilot

Copilot has two support processes: the teammate relay bridge and the Copilot HTTP MCP server. If Copilot is visible but callbacks do not reach Codex, check both:

```zsh
xmux teammateStatus -t <team> copilot-worker
```

If `PANE-STAT` is alive but `HTTP-MCP` or `BRIDGE` is dead, restart the teammate so Copilot reloads MCP config:

```zsh
xmux recover -t <team> copilot-worker --restart-teammate --session <session>
```

If the request text appears in Copilot's input box but the request remains
pending, treat it as a provider TUI submit issue and prefer teammate refresh
through `xmux recover -t <team> copilot-worker --restart-teammate --session
<session>`. Direct submit probes are no longer exposed as an XMux command.

## Provider Logs

When wrapper state is inconclusive, inspect bounded bridge logs:

```zsh
tail -50 /tmp/xmux-bridge-gemini-worker.log
tail -50 /tmp/xmux-bridge-copilot-worker.log
tail -50 /tmp/xmux-bridge-claude-worker.log
```

Common causes:

- MCP setup is missing or stale for the provider.
- The provider CLI is authenticated but did not load the expected MCP server.
- The bridge idle pattern no longer matches the provider TUI.
- A prior support process died after the teammate pane started.

## Raw tmux

Use raw `tmux` only after wrapper and mailbox state are insufficient.

Valid cases:

- `xmux teamStatus` reports stale metadata and actual pane state must be checked.
- A provider wrapper fails before it can resolve or create the teammate pane.
- A bridge is marked dead and process or pane lifecycle needs correlation.
- A CLI-specific TUI input bug must be reproduced.
- The wrapper has no equivalent for the needed observation.

Examples:

```zsh
tmux list-sessions -F '#{session_name}:#{session_id}:#{session_attached}:#{session_windows}'
tmux list-panes -a -F '#{session_name}:#{pane_id}:#{pane_dead}:#{pane_current_command}:#{@xmux-agent}:#{@xmux-team}'
tmux capture-pane -p -t <pane> -S -120
```

Do not use raw `tmux` to send normal work requests, replace `xmux teammateShutdown` or `xmux teamShutdown`, or verify teammate communication when MCP/mailbox request ids are available.

## Reporting

When reporting a debug session, separate:

- Wrapper/MCP state: `xmux teamStatus`, `xmux teammateStatus`, and `team_status`.
- Raw observations: only the facts that required raw `tmux`.
- Recovery action: wrapper command used and whether it changed state.
- Communication result: request ids that received valid responses.

For successful communication checks, report only the teammate-level outcome unless deeper debugging details were requested.
