# XMux Phase Lifecycle

## Team State

Use XMux state as the source of truth:

- `XMUX_TEAM`
- `xmux teammates -t <team>`
- XMux MCP `team_status`
- `<project>/.codex/xmux/teams/<team>/team.json`

Do not rely on Claude Code Agent Teams memory to restore teammates.

## Checkpoints

For long-running feature or epic work, write compact checkpoints under project-local `.codex/xmux/saga/checkpoints/`:

```yaml
team: <team>
phase: <phase>
active_requests:
  - request_id: <id>
    teammate: <name>
    status: pending | completed | blocked
decisions:
  - <short decision>
open_risks:
  - <risk>
```

## Resume

1. Read the latest checkpoint if present.
2. Inspect live team state through XMux.
3. Reconcile missing panes or dead bridges with `xmux stop` and the provider wrapper.
4. Continue from the last completed gate, not from an arbitrary in-progress message.
