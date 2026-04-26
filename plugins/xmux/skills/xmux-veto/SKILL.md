---
name: xmux-veto
description: Use when the user asks for XMux VETO, cross-provider consensus, independent review, gate approval, kill-switch handling, generator-validator separation, or invokes /xmux-veto.
---

# xmux-veto

Use this skill to coordinate cross-provider review under Codex lead.

## Core Rules

- Codex lead coordinates the agenda and consolidates results; it does not count its own opinion as an independent teammate vote.
- Voters are XMux teammates grouped by provider family: `anthropic`, `google`, `github`, `openai`, or `other`.
- Claude can be a teammate in XMux, so do not use the old "non-Claude only" rule. Instead, require provider-family diversity.
- For medium or higher risk, prefer at least two provider families when available.
- Generator and validator should be different teammates; for high risk they should be different provider families.
- Any critical kill-switch finding blocks progress immediately.

## Risk Gates

| Risk | Review Requirement |
| --- | --- |
| Low | Lead review plus tests or one teammate review is enough. |
| Medium | One independent teammate review from a different provider family is required. |
| High | Two provider families or one provider plus explicit human review. |
| Critical | Halt, preserve evidence, and escalate to the user. |

## VETO Flow

1. Define the agenda: artifact, decision, risk, and acceptance criteria.
2. Resolve current team state and choose reviewers.
3. Send one review request per reviewer through XMux MCP/mailbox.
4. Ask each reviewer for `approve`, `request-change`, or `veto` with evidence.
5. Consolidate pessimistically: unresolved critical findings veto the gate; unsupported vetoes become change requests.
6. Record the decision in the response or in `.xmux/saga/checkpoints/` when durable tracking is warranted.

## References

- Read `references/vote-format.md` for the reviewer response schema.
- Read `references/kill-switch.md` when a finding may require immediate halt or user escalation.
