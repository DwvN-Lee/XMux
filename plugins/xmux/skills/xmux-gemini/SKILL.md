---
name: xmux-gemini
description: Use when the user asks Codex lead to add, start, refresh, stop, or delegate to a Gemini teammate in XMux, or invokes /xmux-gemini.
---

# xmux-gemini

Use Gemini as an XMux teammate under Codex lead.

## Runtime

- Start or refresh with `xmux gemini -t <team>`.
- Use `-n <agent>` for task-specific roles.
- Stop with `xmux stop -t <team> <agent>`.
- Inspect bridge health with `xmux teammates -t <team>` and `xmux bridge-status -t <team>`.

## Delegation

- Send work through XMux MCP/mailbox, not raw pane typing from Codex lead.
- Gemini is useful for broad context review, alternative designs, test ideas, and independent verification.
- Keep request ids stable and validate the mailbox response against the user's expected output.
