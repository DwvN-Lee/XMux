---
name: xmux-copilot
description: Use when the user asks Codex lead to add, start, refresh, stop, or delegate to a Copilot teammate in XMux, or invokes /xmux-copilot.
---

# xmux-copilot

Use Copilot as an XMux teammate under Codex lead.

## Runtime

- Start or refresh with `xmux copilot -t <team>`.
- `xmux copilot` prepares the Copilot HTTP MCP bridge so Copilot can call back to the XMux mailbox.
- Stop with `xmux stop -t <team> <agent>`.
- Inspect bridge and HTTP MCP health with `xmux bridge-status -t <team>`.
- If Copilot visibly responds but Codex receives no mailbox response, use scoped `xmux recover -t <team> <agent> --restart-teammate` so it reloads MCP config.

## Delegation

- Use Copilot for code review, repository-aware implementation suggestions, GitHub/PR-oriented checks, and secondary validation.
- Send work through XMux MCP/mailbox and preserve request ids.
- Treat missing MCP callback as a runtime issue, not as a failed review, until the pane is refreshed and retried once.
