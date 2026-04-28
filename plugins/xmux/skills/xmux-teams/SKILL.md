---
name: xmux-teams
description: Use when the user asks Codex lead to configure or operate XMux teammates, delegate work to Gemini, Copilot, Claude, or other providers, verify teammate communication, or mentions "xmux-teams".
---

# xmux-teams

This skill is for Codex running as the XMux lead. The user should be able to describe the desired team behavior in natural language; Codex handles the XMux runtime details.

## Operating Model

- Treat the user's request as declarative. Do not ask the user to run tmux, paste prompts, inspect panes, or manually wire MCP.
- Use existing XMux entrypoints and MCP/mailbox tools. Do not invent one-off subcommands for communication checks.
- Treat an XMux team as a session-scoped runtime. Create or operate the team attached to the current session, and do not reuse archived teams for new work.
- Treat `xmux -n <session>` as the user-facing bootstrap command. Once Codex is running as lead, teammate setup and shutdown are agent-managed.
- Loading this skill is not a discovery step. Do not inspect teams, sessions, bridges, or mailboxes until the user's concrete request has been classified.
- Prefer XMux MCP tools for lead-to-teammate messages: `send_to_teammate`, `wait_teammate_response`, `read_teammate_response`, and `team_status`.
- If MCP is unavailable, use `scripts/xmux_mailbox.py enqueue-request`, `wait-response`, and `team-status`.
- Use role-level XMux commands for normal orchestration: `xmux teamCreate`, `xmux teammateAdd`, `xmux teamStatus`, `xmux teammateStatus`, `xmux teammateShutdown`, and `xmux teamShutdown`.
- Use lower-level wrappers only for diagnostics or provider-specific escape hatches: `xmux doctor`, `xmux pane-info`, `xmux recover`, `xmux ensure`, `xmux send`, and provider wrappers that need explicit provider CLI args.
- Avoid raw `tmux` commands unless an XMux wrapper cannot answer the question. Raw tmux is an implementation detail.

## Agent Friendly Scope

When the user explicitly asks to use XMux teammates for work, treat that as the scope grant to create or attach the requested teammates, send mailbox requests, wait for responses, and perform bounded same-team retries. Do not ask the user to approve each XMux substep inside that requested workflow.

Ask before actions outside that scope: unrelated team operations, raw `tmux`, archive/request/inbox deletion, broad recoveries, or ambiguous shutdown. If the tool runtime requires elevated access to tmux or the user's XMux state, explain that this is a runtime permission boundary rather than a second confirmation of the XMux task.

## Request Boundary

Classify the user's request before running any XMux command:

- Teammate setup in an active XMux lead: resolve only the current session team, then attach the requested providers. Do not create a second lead session.
- Explicit scripted team creation: use `teamCreate` only when the user specifically asks Codex to create a new XMux team/session from automation.
- Add teammate to current team: resolve only the current session team, then attach the requested provider to that team.
- Diagnostics or repair: use `xmux-tools`; broader `xmux sessions` or multi-team inspection is allowed only when the user asks for diagnostics, status, or failure analysis.

Do not run `printenv XMUX_TEAM`, `echo $XMUX_TEAM`, `printf "$XMUX_TEAM"`, unscoped `xmux teammates`, `xmux sessions --all`, archive searches, or cross-project `.codex/xmux/teams` scans as part of normal team setup or teammate attachment. `xmux teamStatus` without `-t` is allowed only as the current-session resolver.

## Team Resolution

1. Use a team name explicitly provided by the user when present.
2. Otherwise run `xmux teamStatus` once and let XMux resolve the current session through tmux pane tags and XMux state.
3. If `xmux teamStatus` cannot resolve a current team, do not scan for reusable teams. For normal teammate setup, report that the user should bootstrap the lead with `xmux -n <session>` from the target project; use `teamCreate` only for explicit scripted team creation.
4. For first-time teammate setup inside an active lead, do not verify that no team exists; attach for the current session directly.
5. For later "add Gemini/Copilot/Claude" requests, use `xmux teamStatus` or `xmux teamStatus -t <explicit-team>` only when status is actually needed.
6. If a team was shutdown and archived, treat it as finished history. Start a new session/team instead of reusing that archived team name.

Run XMux wrappers through the executable entrypoint. Use this resolution order:

1. `xmux <subcommand>` when `xmux` resolves from the Codex shell policy PATH installed by XMux.
2. `$XMUX_INSTALL_DIR/bin/xmux <subcommand>` when `XMUX_INSTALL_DIR` is set.
3. `<xmux-repo>/bin/xmux <subcommand>` when the checkout path is known.
4. From this plugin cache, `../../bin/xmux <subcommand>` relative to the skill directory.
5. Interactive `zsh -ic 'xmux ...'` only as the last compatibility fallback.

```zsh
xmux teamStatus
```

If a sandboxed command returns no output or reports `xmux` as missing, do not treat that as team absence. Retry the same scoped XMux command through an explicit executable path before using the interactive zsh fallback. If the explicit executable is blocked by the Codex command sandbox, request approval for the narrow `xmux` or exact XMux executable prefix; do not switch to `zsh -ic` just to bypass command-prefix approval. Run the executable from the target project cwd, or set `XMUX_PROJECT_DIR`/`XMUX_STATE_DIR` explicitly, so project-local team state resolves correctly.

## Teammate Lifecycle

For requests that name one or more teammates:

1. For the normal `xmux -n <session>` bootstrap flow, run `xmux teammateAdd -t <team> <providers>` for the requested providers after resolving the current team.
2. For explicit scripted team creation, run `xmux teamCreate -t <team> <providers>` and do not scan existing teams first. Provider names are space-separated, for example `gemini copilot`, never comma-separated.
3. Use `xmux teamStatus`, `xmux teamStatus -t <team>`, or `xmux teammateStatus -t <team> <agent>` only when the user asked for status/diagnostics or a prior operation failed.
4. Do not send MCP/mailbox requests to a provider that is not registered in the team. If status shows only `codex-lead`, attach the requested teammate first.

If a teammate pane is alive but its bridge is dead, prefer a full refresh through `xmux teammateShutdown -t <team> <agent>` followed by `xmux teammateAdd -t <team> <provider>`.

## Shutdown Lifecycle

- Use `xmux teammateShutdown -t <team> <agent>` only for scoped teammate shutdown; the team remains active and is not archived.
- Use `xmux teamShutdown -t <team>` for finished team lifecycle. This archives the team state under `.codex/xmux/archive/`.
- After team shutdown/archive, do not continue routing work to that team. A future task should create a fresh session-scoped team.

## Communication Check

For user requests that ask Codex to verify teammate communication:

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
