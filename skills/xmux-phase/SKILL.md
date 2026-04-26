---
name: xmux-phase
description: Use when the user asks for XMux phase workflow, phased implementation, staged design/build/verify flow, cross-provider routing, or invokes /xmux-phase. Codex is the XMux lead; Claude, Gemini, Copilot, and future providers are tmux-backed teammates.
---

# xmux-phase

Use this skill to run a phased engineering workflow with Codex as XMux lead.

## Core Rules

- Codex lead owns scoping, routing, consolidation, and final user reporting.
- Teammates execute delegated work through XMux MCP/mailbox APIs.
- Use `xmux` wrappers for runtime orchestration. Do not use external agent-team primitives for XMux teammate management or communication.
- Keep phase depth proportional to risk. Small fixes can use a compact Plan -> Build -> Verify loop.
- For high-risk work, split generator and validator roles across different provider families when available.
- Do not create persistent phase artifacts unless the work warrants them or the user asks for durable records.

## Phase Tracks

| Track | Use When | Required Flow |
| --- | --- | --- |
| Hotfix | Narrow bug, low ambiguity | Scope -> Build -> Verify |
| Feature | Moderate change, user-facing behavior | Spec -> Design -> Build -> Verify -> Refine |
| Epic | Broad architecture or high risk | Brief -> Spec -> Design -> VETO gates -> Build waves -> Independent verify -> Refine |

## XMux Phase Flow

1. Resolve team state with `xmux teammates -t <team>` or the XMux MCP `team_status` tool.
2. Select teammates by role and provider family. Start missing teammates through `xmux claude`, `xmux gemini`, or `xmux copilot`.
3. Create explicit request ids for each delegated task.
4. Send instructions with `send_to_teammate`; fall back to `scripts/xmux_mailbox.py enqueue-request` only when MCP is unavailable.
5. Wait for responses with `wait_teammate_response` or mailbox `wait-response`.
6. Consolidate evidence into the next phase decision.
7. For verification phases, avoid assigning the same teammate as both generator and validator.

## References

- Read `references/protocol.md` when you need exact message shapes or phase loop rules.
- Read `references/evidence-pack.md` when collecting teammate outputs for gate decisions.
- Read `references/lifecycle.md` when resuming, repairing, or compacting long-running XMux phase work.
