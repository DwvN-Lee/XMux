---
name: xmux-claude
description: Use when the user asks Codex lead to add, start, refresh, shutdown, or delegate to a Claude teammate in XMux, or invokes /xmux-claude.
---

# xmux-claude

Use Claude as an XMux teammate under Codex lead.

## Runtime

- Run XMux through the explicit executable selected by `xmux-teams`; do not depend on `.zshrc` or bare `xmux` for agent-managed steps.
- Start/add with `xmux teammateAdd -t <team> claude`.
- Use the user-provided team or the current session team. Do not scan unrelated teams to find a reusable Claude teammate.
- Resolve or inspect the current team with `xmux teamStatus`; use `xmux teamStatus -t <team>` only when the user gave a team. Do not probe `$XMUX_TEAM` directly.
- Use the lower-level `xmux claude -t <team> -n <agent>` only when a custom teammate name is required.
- Shutdown one teammate with `xmux teammateShutdown -t <team> <agent>`.
- Inspect with `xmux teamStatus -t <team>`, `xmux teammateStatus -t <team>`, and `xmux paneInfo <agent> -t <team>`.

## Delegation

- Send work through XMux MCP `send_to_teammate` or mailbox fallback.
- Send only to a registered active Claude teammate. If Claude is not registered, attach it with `xmux teammateAdd` first.
- Require Claude to respond through its XMux bridge path, preserving the request id.
- Use Claude for language-heavy critique, requirements review, edge-case exploration, and adversarial reasoning.
- Do not treat Claude as the lead in XMux; Codex remains the lead and final consolidator.
