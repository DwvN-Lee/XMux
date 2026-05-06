---
name: xmux-gemini
description: "Use when the user asks Codex to involve Gemini as the single XMux teammate for broad review, design alternatives, test ideas, independent verification, or explicitly invokes $xmux-gemini."
---

# xmux-gemini

Use `$xmux-gemini` to configure Gemini as the single split-view teammate in the current lead session and route work through XMux MCP.

## Setup

1. Resolve the current team with `xmux teamStatus`.
2. Add Gemini to the current lead session:

```zsh
xmux teammateAdd -t <team> gemini
```

## MCP Request

Use Gemini for broad context review, alternative designs, test ideas, and independent verification.

1. Send the Gemini instruction with `send_to_teammate`.
2. Wait with `wait_teammate_response`.
3. Read the result with `read_teammate_response`.
4. Synthesize Gemini's response into Codex's final answer.
