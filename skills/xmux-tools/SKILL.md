---
name: xmux-tools
description: Use for XMux runtime diagnostics, tmux teammate inspection, mailbox debugging, bridge health checks, safe stop/refresh operations, or invokes /xmux-tools.
---

# xmux-tools

Use this skill for operational diagnostics and maintenance of the XMux runtime.

## Preferred Commands

- `xmux sessions`
- `xmux teammates -t <team>`
- `xmux pane-info <agent> -t <team>`
- `xmux doctor -t <team>`
- `xmux bridge-status -t <team>`
- `xmux send <target> "text"`
- `xmux stop -t <team> <agent>`
- `xmux recover -t <team> <agent> --restart-bridge|--restart-teammate`
- `xmux submit-test -t <team> <agent> --text /help`
- `xmux claude|gemini|copilot -t <team>`

## Diagnostic Order

1. Confirm the team name from `$XMUX_TEAM` or `xmux teammates`.
2. Check whether the teammate pane is alive.
3. Check whether the bridge pid is alive.
4. Check unread inbox or pending request state through XMux MCP/mailbox.
5. Refresh only the affected teammate.

Use `xmux doctor` or `xmux bridge-status` before raw tmux/ps diagnostics. They are read-only wrappers for sessions, panes, bridge pid status, mailbox counts, pending request ids, idle patterns, submit delay, and bridge logs.

## Safety

- Do not stop the Codex lead pane through `xmux stop`.
- Prefer wrapper commands over raw `tmux`.
- Use `xmux recover` only with explicit team, agent, and action scope.
- Use `xmux submit-test` only for scoped TUI submit reproduction; normal communication checks must stay on MCP/mailbox request ids.
- Do not delete mailbox files to "fix" state; mark or drain messages through XMux tooling.
- Preserve logs and request ids when reporting failures.
