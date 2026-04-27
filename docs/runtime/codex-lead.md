Back to [README](../../README.md)

# XMux Codex Lead

XMux is a Codex-led teammate runtime. `xmux.zsh` starts Codex as the lead and uses `<project>/.codex/xmux/teams/<team>` for team state by default.

## Runtime Paths

XMux path variables are split by responsibility:

- `XMUX_INSTALL_DIR`: XMux source/install directory, such as `/Users/idongju/Desktop/Git/XMux`.
- `XMUX_PROJECT_DIR`: project root where Codex is working.
- `XMUX_STATE_DIR`: project-local runtime state, usually `$XMUX_PROJECT_DIR/.codex/xmux`.

## Usage

Use the shell-configured XMux entrypoint. For Codex automation, prefer an interactive zsh so `.zshrc` loads the local wrapper:

```zsh
zsh -ic 'xmux start -n refactor -T refactor-team'
```

Start a Codex lead session:

```zsh
xmux start -n refactor -T refactor-team
```

For compatibility, `xmux -n refactor -T refactor-team` still starts the lead.
By default, when the Codex lead process exits, XMux shuts down non-lead
teammates and archives the team state. Use
`--keep-team-on-lead-exit` only when preserving live panes for debugging:

```zsh
xmux start -n refactor -T refactor-team --keep-team-on-lead-exit
```

Start Codex and spawn initial teammates:

```zsh
xmux -n refactor -T refactor-team --claude --gemini --copilot -- --model gpt-5
```

Spawn teammates later from an XMux tmux session or by naming the team:

```zsh
xmux claude -t refactor-team
xmux gemini -t refactor-team
xmux copilot -t refactor-team
```

The old provider functions (`xmux-claude`, `xmux-gemini`, `xmux-copilot`) remain as compatibility wrappers, but user-facing operation should prefer the single `xmux` entrypoint.

Inspect and operate the tmux-backed runtime through XMux wrappers:

```zsh
xmux sessions
xmux teammates -t refactor-team
xmux ensure -t refactor-team --all --bridge --ready --json
xmux pane-info refactor-team:gemini-worker -n 40
xmux doctor -t refactor-team
xmux bridge-status -t refactor-team
xmux recover -t refactor-team gemini-worker --restart-bridge
xmux submit-test -t refactor-team copilot-worker --text /help
xmux send refactor-team:gemini-worker "check the failing test" --clear
xmux attach refactor-team:gemini-worker
xmux stop -t refactor-team gemini-worker
xmux shutdown -t refactor-team --reason manual-shutdown
```

This keeps higher-level workflows from depending on raw `tmux list-panes`, `tmux capture-pane`, `tmux paste-buffer`, or `tmux attach-session` commands. Those calls remain implementation details inside `xmux.zsh`.

Before pinging teammates, run `xmux ensure -t <team> --all --bridge --ready --json`. It resolves active non-lead teammates, classifies stale panes and pid files, repairs targeted bridge and provider MCP setup where it can, and returns a ready/degraded JSON payload without deleting mailbox request history. Use explicit agent names instead of `--all` to scope repair to a subset.

Diagnostics are split by risk. `xmux doctor` and `xmux bridge-status` are read-only wrappers for sessions, panes, bridge pid files, mailbox counts, pending request ids, idle patterns, submit delays, and bridge logs. `xmux ensure`, `xmux recover`, and `xmux submit-test` are mutating wrappers and require an explicit team and teammate target or `--all`.

Lifecycle commands are split by scope. `xmux stop -t <team> <agent>` stops one
teammate and keeps the team live. `xmux shutdown -t <team>` stops non-lead
teammates, cleans bridge and Copilot HTTP MCP pid state, preserves mailbox and
request history, and moves `<project>/.codex/xmux/teams/<team>` to
`<project>/.codex/xmux/archive/<timestamp>-<team>` unless `--no-archive` is
used. A non-archived shutdown leaves `team.json` marked `status: shutdown`, so
unscoped active listings no longer treat it as live.

When a wrapper or MCP tool cannot answer a runtime failure, use the limited escape-hatch process in [XMux Debugging](../operations/debugging.md).

There is intentionally no `xmux-codex` teammate wrapper. In XMux, Codex is the lead. If you need another Codex-led effort, start another `xmux` session with a distinct team.

## Architecture

`xmux` launches or attaches a tmux session supervised by a small shell wrapper
that runs `codex`, preserves Codex's exit status, and then runs
`xmux shutdown -t "$XMUX_TEAM" --reason lead-exit --lead-already-exiting` when
lead-exit shutdown is enabled. It initializes the team through
`scripts/xmux_mailbox.py init-team`, records the lead pane in
`<project>/.codex/xmux/teams/<team>/.lead-pane`, and tags the lead pane with
`@xmux-agent=codex-lead` and `@xmux-team=<team>`.

XMux does not create a per-team `Codex home environment variable` for the Codex lead. It also unsets any inherited `Codex home environment variable` before launching Codex, so Codex runs like a normal session using the user's canonical `~/.codex` runtime. `xmux` writes the `xmux_lead` MCP server config to the canonical Codex config so Codex can call:

- `send_to_teammate`
- `wait_teammate_response`
- `read_teammate_response`
- `list_teammate_events`
- `team_status`

`xmux` enables the repo-local XMux Codex plugin from the canonical Codex config and installs it into Codex's local plugin cache. The plugin exposes `/xmux-teams`, `/xmux-claude`, `/xmux-gemini`, `/xmux-copilot`, and `/xmux-tools`. These are the Codex-lead orchestration contracts: users can ask for teammates, provider-specific teammates, and diagnostics in natural language, while Codex handles teammate liveness, bridge setup, MCP/mailbox delivery, and response validation through existing XMux wrappers and tools. An already-running Codex lead may need to be restarted once after plugin commands change, because slash command discovery is loaded from the Codex home config.

Teammate wrappers create a pane next to the recorded lead pane. Each teammate gets:

- `XMUX_INSTALL_DIR=<xmux install dir>`
- `XMUX_PROJECT_DIR=<project>`
- `XMUX_STATE_DIR=<project>/.codex/xmux`
- `XMUX_OUTBOX=<project>/.codex/xmux/teams/<team>/inboxes/codex-lead.json`
- `XMUX_AGENT=<agent_name>`
- `XMUX_TEAM=<team>`
- tmux pane options `@xmux-agent`, `@xmux-team`, and `@xmux-bridge`

`xmux-bridge.zsh` is only the lead-to-teammate relay. It polls `<project>/.codex/xmux/teams/<team>/inboxes/<agent>.json`, pastes unread prompt text into the teammate pane, includes `[request_id: ...]` when present, then marks the message read.

## Codex Read Model

Codex should not be driven by blind paste injection for lead inbox reads. The lead pane is recorded so a background alarm can wake the lead, but the lead should read messages through the XMux MCP server. That keeps message acknowledgement explicit: the alarm says work exists, and Codex calls MCP read tools to inspect and mark the mailbox state.

This differs from teammate panes. Teammates are external CLIs without lead ownership, so the bridge may paste lead requests into their panes. Their replies return through MCP/write-to-lead using `XMUX_OUTBOX`.
