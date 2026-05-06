---
name: xmux-diagnosis
description: "Use when the user asks for XMux runtime status, failure analysis, bridge or pane health checks, scoped recovery, teammate refresh, shutdown, mailbox debugging, or explicitly invokes $xmux-diagnosis."
---

# xmux-diagnosis

Use `$xmux-diagnosis` for XMux runtime diagnostics and maintenance. Keep normal teammate setup and review orchestration in `$xmux-teams` or the provider-specific skills.

## Read-Only Checks

- `xmux sessions`
- `xmux teamStatus`
- `xmux teamStatus -t <team>`
- `xmux doctor -t <team>`
- `xmux teammateStatus -t <team>`
- `xmux paneInfo <agent> -t <team>`

## Mutating Repairs

- `xmux recover -t <team> <agent> --restart-bridge|--restart-teammate`
- `xmux teammateShutdown -t <team> <agent>`
- `xmux teammateAdd -t <team> claude|gemini|copilot`
- `xmux teamShutdown -t <team>`

Run mutating repairs only with explicit user intent for that team and target. Do not use `recover` without an explicit team, agent, and action.

## Diagnostic Flow

1. Run `xmux teamStatus` once to resolve the current team and show registered members; use `xmux teamStatus -t <team>` only when the user provided the team.
2. Check teammate pane liveness, bridge pid state, and Copilot HTTP MCP pid state when relevant.
3. Check unread inbox, pending request ids, idle patterns, submit delay, and bridge logs through XMux wrappers or MCP/mailbox tooling.
4. Use `xmux doctor` or `xmux teammateStatus` before raw tmux or process diagnostics.
5. Refresh only the affected teammate when repair is requested.

Do not run `printenv XMUX_TEAM`, `echo $XMUX_TEAM`, or `printf "$XMUX_TEAM"` to discover the team. Do not scan unrelated teams to find reusable teammates. XMux teams are session-scoped, and archived teams are history.

Use this executable order for XMux wrappers: `xmux`, then `$XMUX_INSTALL_DIR/bin/xmux`, then interactive `zsh -ic` only as a compatibility fallback. If a sandboxed command returns no output or `xmux` is missing, treat it as an execution-environment failure and retry through the explicit executable path.

## Safety

- Do not shutdown the Codex lead pane through `xmux teammateShutdown`.
- Use `xmux teamShutdown -t <team>` for finished team lifecycle so the team state moves to archive.
- Prefer wrapper commands over raw `tmux`.
- Direct TUI submit probes are not exposed as an XMux command; normal communication checks must stay on MCP/mailbox request ids.
- Do not delete mailbox files to fix state; mark or drain messages through XMux tooling.
- Preserve logs and request ids when reporting failures.
