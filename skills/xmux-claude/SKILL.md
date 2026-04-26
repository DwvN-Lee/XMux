---
name: xmux-claude
description: Use when the user asks Codex lead to add, start, refresh, stop, or delegate to a Claude teammate in XMux, or invokes /xmux-claude.
---

# xmux-claude

Use Claude as an XMux teammate under Codex lead.

## Runtime

- Start or refresh with `xmux claude -t <team>`.
- Use `-n <agent>` when the teammate role should be task-specific.
- Stop with `xmux stop -t <team> <agent>`.
- Inspect with `xmux teammates -t <team>`, `xmux bridge-status -t <team>`, and `xmux pane-info <agent> -t <team>`.

## Delegation

- Send work through XMux MCP `send_to_teammate` or mailbox fallback.
- Require Claude to respond through its XMux bridge path, preserving the request id.
- Use Claude for language-heavy critique, requirements review, edge-case exploration, and adversarial reasoning.
- Do not treat Claude as the lead in XMux; Codex remains the lead and final consolidator.
