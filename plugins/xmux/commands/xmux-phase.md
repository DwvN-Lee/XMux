---
description: Run the XMux phase workflow with Codex as lead
argument-hint: [phase request]
allowed-tools: [Bash, Read, Write, Edit]
---

# /xmux-phase

Use the `xmux-phase` skill to run a phased XMux workflow for the user's request.

User request:

```text
$ARGUMENTS
```

## Workflow

1. Classify the request size and risk before choosing the phase depth.
2. Resolve the active XMux team and prepare only the teammates needed for the phase.
3. Use XMux MCP/mailbox APIs for delegation and response collection.
4. Keep generator and validator roles separated when verification is required.
5. Record phase decisions and evidence in project files only when the requested work warrants persistent artifacts.

Do not use external agent-team primitives. XMux is Codex-led and uses tmux-backed teammates through the `xmux` entrypoint.
