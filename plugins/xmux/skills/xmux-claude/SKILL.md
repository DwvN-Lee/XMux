---
name: xmux-claude
description: "Operate a Claude XMux teammate under Codex lead: attach, refresh, shutdown, inspect, or delegate Claude-specific critique/review work when the user asks for Claude or explicitly invokes $xmux-claude. Use $xmux-teams for shared lifecycle and routing rules."
---

# xmux-claude

Use Claude as an XMux teammate. Codex remains the lead and final consolidator.

## Runtime

- Follow `$xmux-teams` for team resolution, executable selection, lifecycle scope, and MCP/mailbox routing.
- Start/add with `xmux teammateAdd -t <team> claude`.
- Use the lower-level `xmux claude -t <team> -n <agent>` only when a custom teammate name is required.
- Inspect Claude with `xmux teammateStatus -t <team> <agent>` or `$xmux-tools` when diagnostics are requested.

## Delegation

- Send only to a registered active Claude teammate. If Claude is not registered, attach it first.
- Use Claude for language-heavy critique, requirements review, edge-case exploration, and adversarial reasoning.
- Require the XMux bridge/mailbox response to preserve the request id.
