---
name: xmux-copilot
description: "Operate a Copilot XMux teammate under Codex lead: attach, refresh, shutdown, inspect, or delegate Copilot-specific code review, repository-aware suggestions, GitHub/PR checks, or secondary validation when the user asks for Copilot or explicitly invokes $xmux-copilot. Use $xmux-teams for shared lifecycle and routing rules."
---

# xmux-copilot

Use Copilot as an XMux teammate. Codex remains the lead and final consolidator.

## Runtime

- Follow `$xmux-teams` for team resolution, executable selection, lifecycle scope, and MCP/mailbox routing.
- Start/add with `xmux teammateAdd -t <team> copilot`.
- `xmux teammateAdd` prepares the Copilot HTTP MCP bridge so Copilot can call back to the XMux mailbox.
- Inspect bridge and HTTP MCP health with `xmux teammateStatus -t <team> <agent>` or `$xmux-tools` when diagnostics are requested.
- If Copilot visibly responds but Codex receives no mailbox response, use scoped `xmux recover -t <team> <agent> --restart-teammate` after diagnostics so it reloads MCP config.

## Delegation

- Send only to a registered active Copilot teammate. If Copilot is not registered, attach it first.
- Use Copilot for code review, repository-aware implementation suggestions, GitHub/PR-oriented checks, and secondary validation.
- Preserve request ids in MCP/mailbox requests and responses.
- Treat missing MCP callback as a runtime issue, not as a failed review, until the pane is refreshed and retried once.
