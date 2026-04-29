---
name: xmux-tools
description: "Diagnose and repair XMux runtime issues under Codex lead: tmux pane inspection, mailbox debugging, bridge health checks, status monitoring, scoped recovery, safe shutdown/refresh operations, or explicit $xmux-tools invocation. Do not use for normal teammate setup; use $xmux-teams."
---

# xmux-tools

Use this skill for XMux diagnostics and runtime maintenance.

This is the diagnostic exception to `$xmux-teams` setup boundaries. Use broader session or team inspection only when the user asks for diagnostics, status, monitoring, or failure analysis.

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
2. Check teammate pane liveness.
3. Check bridge pid and Copilot HTTP MCP pid state when relevant.
4. Check unread inbox, pending request ids, idle patterns, submit delay, and bridge logs through XMux wrappers or MCP/mailbox.
5. Refresh only the affected teammate when repair is requested.

Do not run `printenv XMUX_TEAM`, `echo $XMUX_TEAM`, or `printf "$XMUX_TEAM"` to discover the team. Do not scan unrelated teams to find reusable teammates. XMux teams are session-scoped, and archived teams are history.

Use the same executable order as `$xmux-teams`: `xmux`, then `$XMUX_INSTALL_DIR/bin/xmux`, then interactive `zsh -ic` only as a compatibility fallback. If a sandboxed command returns no output or `xmux` is missing, treat it as an execution-environment failure and retry through the explicit executable path.

Prefer `xmux doctor` or `xmux teammateStatus` before raw tmux/ps diagnostics.

## Safety

- Do not shutdown the Codex lead pane through `xmux teammateShutdown`.
- Use `xmux teamShutdown -t <team>` for finished team lifecycle so the team state moves to archive.
- Prefer wrapper commands over raw `tmux`.
- Direct TUI submit probes are no longer exposed as an XMux command; normal communication checks must stay on MCP/mailbox request ids.
- Do not delete mailbox files to "fix" state; mark or drain messages through XMux tooling.
- Preserve logs and request ids when reporting failures.
