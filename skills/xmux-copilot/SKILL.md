---
name: xmux-copilot
description: Use when the user asks Codex lead to add, start, refresh, shutdown, or delegate to a Copilot teammate in XMux, or invokes /xmux-copilot.
---

# xmux-copilot

Use Copilot as an XMux teammate under Codex lead.

## Runtime

- Run XMux through the explicit executable selected by `xmux-teams`; do not depend on `.zshrc` or bare `xmux` for agent-managed steps.
- Start/add with `xmux teammateAdd -t <team> copilot`.
- Use the user-provided team or the current session team. Do not scan unrelated teams to find a reusable Copilot teammate.
- Resolve or inspect the current team with `xmux teamStatus`; use `xmux teamStatus -t <team>` only when the user gave a team. Do not probe `$XMUX_TEAM` directly.
- `xmux teammateAdd` prepares the Copilot HTTP MCP bridge so Copilot can call back to the XMux mailbox.
- Shutdown one teammate with `xmux teammateShutdown -t <team> <agent>`.
- Inspect bridge and HTTP MCP health with `xmux teammateStatus -t <team>`.
- If Copilot visibly responds but Codex receives no mailbox response, use scoped `xmux recover -t <team> <agent> --restart-teammate` so it reloads MCP config.

## Delegation

- Use Copilot for code review, repository-aware implementation suggestions, GitHub/PR-oriented checks, and secondary validation.
- Send work through XMux MCP/mailbox and preserve request ids.
- Send only to a registered active Copilot teammate. If Copilot is not registered, attach it with `xmux teammateAdd` first.
- Treat missing MCP callback as a runtime issue, not as a failed review, until the pane is refreshed and retried once.
