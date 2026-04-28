---
name: xmux-gemini
description: Use when the user asks Codex lead to add, start, refresh, shutdown, or delegate to a Gemini teammate in XMux, or invokes /xmux-gemini.
---

# xmux-gemini

Use Gemini as an XMux teammate under Codex lead.

## Runtime

- Run XMux through the explicit executable selected by `xmux-teams`; do not depend on `.zshrc` or bare `xmux` for agent-managed steps.
- Start/add with `xmux teammateAdd -t <team> gemini`.
- Use the user-provided team or the current session team. Do not scan unrelated teams to find a reusable Gemini teammate.
- Resolve or inspect the current team with `xmux teamStatus`; use `xmux teamStatus -t <team>` only when the user gave a team. Do not probe `$XMUX_TEAM` directly.
- Use the lower-level `xmux gemini -t <team> -n <agent>` only when a custom teammate name or explicit Gemini CLI args are required.
- Shutdown one teammate with `xmux teammateShutdown -t <team> <agent>`.
- Inspect bridge health with `xmux teamStatus -t <team>` and `xmux teammateStatus -t <team>`.

## Delegation

- Send work through XMux MCP/mailbox, not raw pane typing from Codex lead.
- Send only to a registered active Gemini teammate. If Gemini is not registered, attach it with `xmux teammateAdd` first.
- Gemini is useful for broad context review, alternative designs, test ideas, and independent verification.
- Keep request ids stable and validate the mailbox response against the user's expected output.
