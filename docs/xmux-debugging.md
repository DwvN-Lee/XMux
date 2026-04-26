# XMux Debugging

XMux operation is wrapper-first. Use `xmux` wrappers and XMux MCP/mailbox tools for normal diagnosis, recovery, and communication checks. Raw `tmux` commands are an implementation-level escape hatch only when a wrapper cannot answer the question.

## Default Path

Run wrappers from a shell that already loads XMux. For Codex automation, prefer an interactive zsh so the user's `.zshrc` provides the local wrapper:

```zsh
zsh -ic 'xmux teammates -t <team>'
```

Useful read-only checks:

```zsh
xmux sessions
xmux teammates -t <team>
xmux doctor -t <team>
xmux bridge-status -t <team>
xmux pane-info <agent> -t <team>
python3 scripts/xmux_mailbox.py team-status <team>
```

For lead-to-teammate communication checks, use XMux MCP or mailbox request tracking:

- `team_status`
- `send_to_teammate`
- `wait_teammate_response`
- `read_teammate_response`
- `scripts/xmux_mailbox.py enqueue-request`
- `scripts/xmux_mailbox.py wait-response`

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
xmux claude -t <team> --session <session>
xmux gemini -t <team> --session <session>
xmux copilot -t <team> --session <session>
```

`xmux doctor` and `xmux bridge-status` are read-only. `xmux recover`, `xmux stop`, and `xmux submit-test` mutate runtime state and should always be scoped to an explicit team and agent.

## Copilot

Copilot has two support processes: the teammate relay bridge and the Copilot HTTP MCP server. If Copilot is visible but callbacks do not reach Codex, check both:

```zsh
xmux bridge-status -t <team> copilot-worker
```

If `PANE-STAT` is alive but `HTTP-MCP` or `BRIDGE` is dead, restart the teammate so Copilot reloads MCP config:

```zsh
xmux recover -t <team> copilot-worker --restart-teammate --session <session>
```

If the request text appears in Copilot's input box but the request remains pending, use the scoped submit probe:

```zsh
xmux submit-test -t <team> copilot-worker --text /help --delay 0.8
```

`xmux submit-test` is mutating because it injects input into the provider TUI. Keep it scoped and do not use real work prompts for submit debugging.

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

- `xmux teammates` reports stale metadata and actual pane state must be checked.
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

Do not use raw `tmux` to send normal work requests, replace `xmux stop`, or verify teammate communication when MCP/mailbox request ids are available.

## Reporting

When reporting a debug session, separate:

- Wrapper/MCP state: `xmux teammates`, `xmux bridge-status`, and `team_status`.
- Raw observations: only the facts that required raw `tmux`.
- Recovery action: wrapper command used and whether it changed state.
- Communication result: request ids that received valid responses.

For successful communication checks, report only the teammate-level outcome unless deeper debugging details were requested.
