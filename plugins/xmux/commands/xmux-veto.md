---
description: Run the XMux cross-provider VETO review protocol
argument-hint: [review target]
allowed-tools: [Bash, Read, Write, Edit]
---

# /xmux-veto

Use the `xmux-veto` skill to coordinate cross-provider review for the user's requested artifact or decision.

User request:

```text
$ARGUMENTS
```

## Workflow

1. Identify the review target, risk level, and expected evidence.
2. Resolve the active XMux team and choose independent reviewers by provider family.
3. Send review briefs through XMux MCP/mailbox APIs.
4. Collect reviewer findings and consolidate them pessimistically.
5. Report whether the target is approved, needs changes, or is blocked by a veto.

Codex lead coordinates and consolidates. Teammate votes or findings should come from XMux teammates, not from direct lead self-approval.
