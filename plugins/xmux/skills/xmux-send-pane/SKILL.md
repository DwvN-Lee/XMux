---
name: xmux-send-pane
description: "Send text directly to a specific XMux tmux pane through xmux sendPane. Use when the user explicitly asks for direct pane input, low-level TUI recovery, prompt injection debugging, or manual pane paste; do not use for normal teammate delegation, which should use XMux MCP/mailbox routing."
---

# xmux-send-pane

Use `$xmux-send-pane` for direct pane input through the XMux wrapper. Prefer `$xmux-teams` and XMux MCP/mailbox tools for normal teammate work.

## Command

```zsh
xmux sendPane <target> "<text>" [--clear] [--no-enter] [--force]
```

Targets can be an XMux agent, a pane id, or a scoped target such as `<team>:<agent>` when supported by the runtime.

## Workflow

1. Confirm the user actually needs direct pane input instead of mailbox delegation.
2. Resolve the target with `xmux teamStatus`, `xmux teammateStatus -t <team>`, or `xmux paneInfo <target> -t <team>` when the target is ambiguous.
3. Send with `xmux sendPane` from the project cwd so `XMUX_PROJECT_DIR` and `XMUX_STATE_DIR` resolve correctly.
4. Use `--clear` only when replacing an existing prompt is intended.
5. Use `--no-enter` only when the text should be staged without submission.

## Safety

- Do not send to the Codex lead pane.
- Do not paste secrets, API keys, tokens, or user-private credentials into a pane.
- Do not use `--force` unless the user explicitly asked for a force send or a scoped recovery requires it.
- Do not use raw `tmux send-keys` unless the XMux wrapper cannot perform the requested operation.
- Report the target and outcome briefly; avoid exposing raw pane ids unless debugging was requested.
