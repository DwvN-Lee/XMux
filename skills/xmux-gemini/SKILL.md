---
name: xmux-gemini
description: Operate a Gemini XMux teammate under Codex lead: attach, refresh, shutdown, inspect, or delegate Gemini-specific broad review, design alternatives, tests, or verification when the user asks for Gemini or explicitly invokes $xmux-gemini. Use $xmux-teams for shared lifecycle and routing rules.
---

# xmux-gemini

Use Gemini as an XMux teammate. Codex remains the lead and final consolidator.

## Runtime

- Follow `$xmux-teams` for team resolution, executable selection, lifecycle scope, and MCP/mailbox routing.
- Start/add with `xmux teammateAdd -t <team> gemini`.
- Use the lower-level `xmux gemini -t <team> -n <agent>` only when a custom teammate name or explicit Gemini CLI args are required.
- Inspect Gemini with `xmux teammateStatus -t <team> <agent>` or `$xmux-tools` when diagnostics are requested.

## Delegation

- Send only to a registered active Gemini teammate. If Gemini is not registered, attach it first.
- Use Gemini for broad context review, alternative designs, test ideas, and independent verification.
- Keep request ids stable and validate the mailbox response against the user's expected output.
