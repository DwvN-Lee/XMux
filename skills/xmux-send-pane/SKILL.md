---
name: xmux-send-pane
description: "Use when the user explicitly asks to inject or stage text into a named active XMux lead session or explicit tmux pane through xmux sendPane, including prompt injection debugging, low-level TUI recovery, or manual pane paste."
---

# xmux-send-pane

Use `$xmux-send-pane` for direct prompt injection into an active XMux lead session or explicit tmux pane through the XMux wrapper.

## Command

```zsh
xmux sendPane <target> "<text>" [--clear] [--no-enter] [--force]
```

Targets are active XMux lead session names or explicit tmux pane ids such as `%3`. Plain names like `test` are resolved as active XMux lead/session targets first.

## Workflow

1. Confirm the user wants direct prompt injection or staging into a named XMux lead session or pane.
2. Resolve a named target with `xmux sessions --filter <target>`. If no active target is found, stop and report that the named XMux lead/session is not active.
3. Validate the destination with `xmux paneInfo <target> -n 0` before sending. For explicit pane ids, validate with `xmux paneInfo %<id> -n 0`.
4. Send with `xmux sendPane <target> "<text>"` from the project cwd so `XMUX_PROJECT_DIR` and `XMUX_STATE_DIR` resolve correctly.
5. Use `--clear` only when replacing an existing prompt is intended.
6. Use `--no-enter` only when the text should be staged without submission.

## Safety

- Avoid sending back into the current pane unless the user explicitly intended that destination.
- Do not paste secrets, API keys, tokens, or user-private credentials into a pane.
- Do not use `--force` unless the user explicitly asked for a force send or a recovery context requires it.
- Do not use raw `tmux send-keys` unless the XMux wrapper cannot perform the requested operation.
- Report the target and outcome briefly; avoid exposing raw pane ids unless debugging was requested.
