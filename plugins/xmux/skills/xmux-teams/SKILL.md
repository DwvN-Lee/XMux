---
name: xmux-teams
description: "Operate XMux teams under Codex lead: add, refresh, shutdown, or delegate to Claude/Gemini/Copilot teammates; verify teammate communication; manage session-scoped team lifecycle; or handle explicit $xmux-teams invocation. Use $xmux-tools instead for diagnostics, failure analysis, broad status inspection, or repair."
---

# xmux-teams

Use this skill as the shared orchestration contract for Codex running as the XMux lead.

## Core Contract

- Treat the user's request as declarative. Do not ask the user to run tmux, paste prompts, inspect panes, or manually wire MCP.
- Treat `xmux -n <session>` as the user-facing bootstrap command. Once Codex is running as lead, teammate setup and shutdown are agent-managed.
- Treat an XMux team as a session-scoped runtime. Operate the current session team, and do not reuse archived teams for new work.
- Loading this skill is not a discovery step. Do not inspect teams, sessions, bridges, or mailboxes until the user's concrete request has been classified.
- Prefer XMux MCP tools for lead-to-teammate messages: `send_to_teammate`, `wait_teammate_response`, `read_teammate_response`, and `team_status`.
- If MCP is unavailable, use `scripts/xmux_mailbox.py enqueue-request`, `wait-response`, and `team-status`.
- Use existing XMux wrappers. Do not invent ad hoc subcommands or use raw tmux unless a wrapper cannot answer the question.

## Scope

When the user asks to use XMux teammates, treat that as scope to create or attach the requested teammates, send mailbox requests, wait for responses, and perform bounded same-team retries.

Ask before actions outside that scope: unrelated team operations, raw tmux, archive/request/inbox deletion, broad recoveries, or ambiguous shutdown. If the runtime requires elevated tmux or XMux state access, explain it as a runtime permission boundary.

## Request Classification

- Current lead teammate setup: resolve only the current session team, then attach requested providers.
- Explicit scripted team creation: use `xmux teamCreate` only when the user asks Codex to create a new team/session from automation.
- Add teammate to current team: resolve only the current session team, then attach the provider.
- Diagnostics, monitoring, or repair: use `$xmux-tools`.

Do not run environment probes such as `printenv XMUX_TEAM`, unscoped `xmux teammates`, `xmux sessions --all`, archive searches, or cross-project `.codex/xmux/teams` scans during normal setup. `xmux teamStatus` without `-t` is allowed only as the current-session resolver.

## Team Resolution

1. Use a team name explicitly provided by the user.
2. Otherwise run `xmux teamStatus` once and let XMux resolve the current session through pane tags and state.
3. If no current team resolves, report that the user should bootstrap Codex with `xmux -n <session>` from the target project. Do not scan for reusable teams.
4. Treat shutdown or archived teams as finished history.

Use this executable order for XMux wrappers:

1. `xmux <subcommand>` when `xmux` resolves from the Codex shell policy PATH installed by XMux.
2. `$XMUX_INSTALL_DIR/bin/xmux <subcommand>` when `XMUX_INSTALL_DIR` is set.
3. Interactive `zsh -ic 'xmux ...'` only as the last compatibility fallback.

If a sandboxed command returns no output or says `xmux` is missing, treat it as an execution-environment failure, not team absence. Retry the same scoped command through the explicit executable path before the interactive fallback. Do not derive a checkout-relative executable path from this skill directory. Run from the target project cwd, or set `XMUX_PROJECT_DIR`/`XMUX_STATE_DIR` explicitly.

## Teammate Lifecycle

- Add providers with `xmux teammateAdd -t <team> <providers>` after resolving the current team.
- For explicit scripted creation, run `xmux teamCreate -t <team> <providers>`. Provider names are space-separated, for example `gemini copilot`.
- Do not send MCP/mailbox requests to an unregistered provider. Attach the teammate first.
- If a teammate pane is alive but its bridge is dead, refresh with `xmux teammateShutdown -t <team> <agent>` followed by `xmux teammateAdd -t <team> <provider>`.

## Shutdown Lifecycle

- Use `xmux teammateShutdown -t <team> <agent>` only for scoped teammate shutdown; the team remains active and is not archived.
- Use `xmux teamShutdown -t <team>` for finished team lifecycle. This archives the team state under `.codex/xmux/archive/`.
- After team shutdown/archive, do not continue routing work to that team. A future task should create a fresh session-scoped team.

## Communication Check

1. Derive the expected response contract from the user's request. Do not hard-code a validation phrase inside this skill.
2. Confirm each target is a registered teammate agent, or a provider alias that resolves to exactly one registered active teammate.
3. Create one request per teammate with a stable request id.
4. Send the teammate instruction through MCP/mailbox, not direct pane paste.
5. Wait for each request id and validate the returned message against the expected response contract.
6. If a response is missing or invalid, retry once with a correction prompt that preserves the original request id.
7. Report success or the smallest useful failure diagnosis.

## User-Facing Reporting

- Keep the final response short.
- Do not expose internal pane ids, tmux commands, or mailbox paths unless debugging was requested.
- For successful communication checks, state that the requested teammate responses were received.
- For failure, identify the teammate and whether the failure was spawn, bridge, timeout, or response validation.
