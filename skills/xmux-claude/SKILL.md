---
name: xmux-claude
description: "Use when the user asks Codex to involve Claude as the single XMux teammate for critique, requirements review, edge-case exploration, adversarial reasoning, or explicitly invokes $xmux-claude."
---

# xmux-claude

Use `$xmux-claude` to configure Claude as the single split-view teammate in the current lead session and route work through XMux MCP.

## Setup

1. Resolve the current team with `xmux teamStatus`.
2. Add Claude to the current lead session:

```zsh
xmux teammateAdd -t <team> claude
xmux ensure -t <team> claude-worker --bridge --ready --json
```

## MCP Request

Use Claude for language-heavy critique, requirements review, edge-case exploration, and adversarial reasoning.

1. Send the Claude instruction with `send_to_teammate`.
2. Wait with `wait_teammate_response`.
3. Read the result with `read_teammate_response`.
4. Synthesize Claude's response into Codex's final answer.
