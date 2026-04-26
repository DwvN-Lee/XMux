---
description: Configure and operate XMux teammates from a natural-language request
argument-hint: [team request]
allowed-tools: [Bash, Read]
---

# /xmux-teams

Use the `xmux-teams` skill and handle the user's request as a declarative XMux teammate orchestration task.

User request:

```text
$ARGUMENTS
```

## Workflow

1. Resolve the active XMux team from the runtime environment first. If unavailable, inspect the current XMux team state through the `xmux` entrypoint.
2. Prepare only the teammates needed by the user request. Use `xmux` wrappers for runtime orchestration and diagnostics.
3. Send teammate instructions through XMux MCP/mailbox APIs. Do not rely on direct pane paste from the lead unless no XMux API path is available.
4. Wait for teammate responses through XMux MCP/mailbox APIs and validate them against the user's requested outcome.
5. Report the result briefly. Hide pane ids, mailbox paths, and bridge internals unless the user explicitly asks for debugging details.

## Constraints

- Keep this command provider-neutral: Gemini, Copilot, Claude, and future teammates should follow the same XMux flow.
- Do not introduce a dedicated test command for communication checks. Treat checks as normal teammate instructions.
- Do not hard-code a specific validation phrase into this command. The expected response contract comes from the user request.
- Prefer `xmux` as the single shell entrypoint over raw `tmux`.
