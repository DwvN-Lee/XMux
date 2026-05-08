---
name: xmux-teams
description: "Use when the user asks Codex to coordinate XMux cross review, multi-teammate review, or two-or-more named Claude/Gemini/Copilot teammates, or explicitly invokes $xmux-teams."
---

# xmux-teams

Use `$xmux-teams` to configure multiple XMux teammates as split-view panes in the current lead session and coordinate review through XMux MCP.

## Provider Selection

- For cross-review or team-review requests without provider names, use all built-in providers: `claude gemini copilot`.
- When the user names two or more providers, use only those providers.
- When the user names exactly one provider, use that provider's skill instead: `$xmux-claude`, `$xmux-gemini`, or `$xmux-copilot`.
- Provider names are space-separated for XMux commands.

## Setup

1. Resolve the current team with `xmux teamStatus`.
2. Add the selected providers to the current lead session:

```zsh
xmux teammateAdd -t <team> claude gemini copilot
xmux ensure -t <team> --all --bridge --ready --json
```

For a subset:

```zsh
xmux teammateAdd -t <team> claude gemini
xmux ensure -t <team> claude-worker gemini-worker --bridge --ready --json
```

## MCP Review Flow

1. Convert the user's request into one instruction per teammate.
2. Send each instruction with `send_to_teammate`.
3. Wait with `wait_teammate_response`.
4. Read results with `read_teammate_response`.
5. Synthesize the teammate responses into Codex's final answer.
