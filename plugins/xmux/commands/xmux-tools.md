---
description: Diagnose and operate the XMux tmux teammate runtime
argument-hint: [diagnostic request]
allowed-tools: [Bash, Read]
---

# /xmux-tools

Use the `xmux-tools` skill for XMux runtime diagnostics, session inspection, mailbox state, bridge health, scoped recovery, and safe teammate teardown.

User request:

```text
$ARGUMENTS
```

Prefer `xmux` wrapper commands over raw `tmux`. Start with read-only `xmux doctor`, `xmux bridge-status`, `xmux teammates`, `xmux sessions`, `xmux pane-info`, and MCP/mailbox tools. Use mutating `xmux recover` or `xmux submit-test` only with an explicit team and teammate target. Use raw `tmux` only when the wrapper cannot answer the diagnostic question.
