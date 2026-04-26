---
name: xmux-teams
description: Use when the user asks Codex lead to configure or operate XMux teammates, delegate work to Gemini, Copilot, Claude, or other providers, verify teammate communication, or mentions "xmux-teams".
---

# xmux-teams

This skill is for Codex running as the XMux lead. The user should be able to describe the desired team behavior in natural language; Codex handles the XMux runtime details.

## Operating Model

- Treat the user's request as declarative. Do not ask the user to run tmux, paste prompts, inspect panes, or manually wire MCP.
- Use existing XMux entrypoints and MCP/mailbox tools. Do not invent one-off subcommands for communication checks.
- Prefer XMux MCP tools for lead-to-teammate messages: `send_to_teammate`, `wait_teammate_response`, `read_teammate_response`, and `team_status`.
- If MCP is unavailable, use `scripts/xmux_mailbox.py enqueue-request`, `wait-response`, and `team-status`.
- Use shell wrappers only for runtime orchestration and diagnostics: `xmux teammates`, `xmux doctor`, `xmux bridge-status`, `xmux gemini`, `xmux copilot`, `xmux claude`, `xmux pane-info`, `xmux recover`, `xmux stop`.
- Avoid raw `tmux` commands unless an XMux wrapper cannot answer the question. Raw tmux is an implementation detail.

## Team Resolution

1. Determine the team from `$XMUX_TEAM`.
2. If absent, inspect current XMux state through `xmux teammates`.
3. If still unknown, ask the user to start or identify an XMux team.

Run XMux wrappers through the user's configured shell environment. If automation does not already expose `xmux`, prefer an interactive zsh so `.zshrc` loads the local wrapper:

```zsh
zsh -ic 'xmux teammates -t "$XMUX_TEAM"'
```

## Ensure Teammates

For requests that name one or more teammates:

1. Inspect current state with `xmux teammates -t <team>`.
2. Start or refresh only the missing, inactive, or disconnected teammates required by the request.
3. Re-run `xmux teammates -t <team>` and proceed only when each required teammate is alive and its bridge is alive.

If a teammate pane is alive but its bridge is dead, prefer a full refresh through `xmux stop` followed by the provider wrapper for that teammate.

## Communication Check

For user requests that ask Codex to verify teammate communication:

1. Derive the expected response contract from the user's request. Do not hard-code a validation phrase inside this skill.
2. Create one request per teammate with a stable request id.
3. Send the teammate instruction through MCP/mailbox, not direct pane paste.
4. Wait for each request id and validate the returned message against the expected response contract.
5. If a response is missing or invalid, retry once with a correction prompt that preserves the original request id.
6. Report success or the smallest useful failure diagnosis.

## User-Facing Reporting

- Keep the final response short.
- Do not expose internal pane ids, tmux commands, or mailbox paths unless debugging was requested.
- For successful communication checks, state that the requested teammate responses were received.
- For failure, identify the teammate and whether the failure was spawn, bridge, timeout, or response validation.
