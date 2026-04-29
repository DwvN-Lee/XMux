---
name: xmux-tools
description: Use for XMux runtime diagnostics, tmux teammate inspection, mailbox debugging, bridge health checks, safe shutdown/refresh operations, or invokes /xmux-tools.
---

# xmux-tools

Use this skill for operational diagnostics and maintenance of the XMux runtime.

This skill is the diagnostic exception to `xmux-teams` setup boundaries. Use broader session or team inspection only when the user asks for diagnostics, status, monitoring, or failure analysis.

## Preferred Commands

- `xmux sessions`
- `xmux teamStatus`
- `xmux teamStatus -t <team>`
- `xmux paneInfo <agent> -t <team>`
- `xmux doctor -t <team>`
- `xmux teammateStatus -t <team>`
- `xmux sendPane <target> "text"`
- `xmux teammateShutdown -t <team> <agent>`
- `xmux recover -t <team> <agent> --restart-bridge|--restart-teammate`
- `xmux teammateAdd -t <team> claude|gemini|copilot`

## Diagnostic Order

1. Run `xmux teamStatus` once to resolve the current team and show registered members; use `xmux teamStatus -t <team>` only when the user provided the team.
2. Do not run `printenv XMUX_TEAM`, `echo $XMUX_TEAM`, or `printf "$XMUX_TEAM"` to discover the team.
3. Check whether the teammate pane is alive.
4. Check whether the bridge pid is alive.
5. Check unread inbox or pending request state through XMux MCP/mailbox.
6. Refresh only the affected teammate.

Do not scan unrelated teams to find a reusable team. XMux teams are session-scoped; once a team is shutdown and archived, treat it as historical state and start a new session/team for future work.

Prefer the executable entrypoint. Use `xmux <subcommand>` when `xmux` resolves from the Codex shell policy PATH installed by XMux; otherwise use `$XMUX_INSTALL_DIR/bin/xmux <subcommand>`. Do not derive a checkout-relative executable path from this skill directory. If a sandboxed Codex command returns no output or `xmux` is not found, do not infer that no team exists. Treat it as an execution-environment failure and rerun the same scoped wrapper through an explicit executable path before falling back to the user's interactive zsh/XMux runtime. If the command is blocked by the Codex command sandbox, request approval for the narrow `xmux` or exact XMux executable prefix; do not switch to `zsh -ic` just to bypass command-prefix approval. Run the executable from the target project cwd, or set `XMUX_PROJECT_DIR`/`XMUX_STATE_DIR` explicitly, so project-local state resolves correctly.

When the user requested XMux diagnostics, bounded read-only status checks are inside scope. Mutating repair commands such as `recover` or broad shutdown still require explicit user intent for that target and team.

Use `xmux doctor` or `xmux teammateStatus` before raw tmux/ps diagnostics. They are read-only wrappers for sessions, panes, bridge pid status, mailbox counts, pending request ids, idle patterns, submit delay, and bridge logs.

## Safety

- Do not shutdown the Codex lead pane through `xmux teammateShutdown`.
- Use `xmux teamShutdown -t <team>` for finished team lifecycle so the team state moves to archive.
- Prefer wrapper commands over raw `tmux`.
- Use `xmux recover` only with explicit team, agent, and action scope.
- Direct TUI submit probes are no longer exposed as an XMux command; normal communication checks must stay on MCP/mailbox request ids.
- Do not delete mailbox files to "fix" state; mark or drain messages through XMux tooling.
- Preserve logs and request ids when reporting failures.
