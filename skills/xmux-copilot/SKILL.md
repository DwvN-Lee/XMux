---
name: xmux-copilot
description: "Use when the user asks Codex to involve Copilot as the single XMux teammate for code review, repository-aware suggestions, PR or GitHub checks, secondary validation, or explicitly invokes $xmux-copilot."
---

# xmux-copilot

Use `$xmux-copilot` to configure Copilot as the single split-view teammate in the current lead session and route work through XMux MCP.

## Setup

1. Resolve the current team with `xmux teamStatus`.
2. Add Copilot to the current lead session:

```zsh
xmux teammateAdd -t <team> copilot
xmux ensure -t <team> copilot-worker --bridge --ready --json
```

## MCP Request

Use Copilot for code review, repository-aware implementation suggestions, GitHub/PR-oriented checks, and secondary validation.

1. Send the Copilot instruction with `send_to_teammate`.
2. Wait with `wait_teammate_response`.
3. Read the result with `read_teammate_response`.
4. Synthesize Copilot's response into Codex's final answer.
