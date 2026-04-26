# XMux Phase Protocol

## Message Shapes

Delegation prompt:

```text
[XMUX DISPATCH]
request_id: <stable-id>
phase: <P0|P1|P2|P3|P4|P5>
role: <teammate role>
objective: <specific objective>
constraints: <hard constraints>
expected_output: <format and acceptance criteria>
```

Completion response:

```text
[XMUX COMPLETION]
request_id: <same stable id>
status: completed | blocked | needs-input
summary: <short result>
evidence: <files, commands, findings, or reasoning>
next_action: <recommended next step>
```

Review response:

```text
[XMUX REVIEW]
request_id: <same stable id>
verdict: approve | request-change | veto
risk: low | medium | high | critical
findings: <ordered findings with evidence>
```

## Phase Loops

- P0 Brief: confirm task type, risk, scope, team needs.
- P1 Spec: clarify expected behavior and constraints.
- P2 Design: decide approach, interfaces, migration plan, and tests.
- P3 Build: implement in bounded waves.
- P4 Verify: independent review, test execution, and risk assessment.
- P5 Refine: fix verification findings and update docs or specs when needed.

For hotfixes, P1 and P2 can be compressed into the implementation plan. For epics, do not skip P1/P2 gates.

## Communication

- Lead to teammate: XMux MCP `send_to_teammate`.
- Teammate to lead: teammate MCP `write_to_lead`, stored in the XMux mailbox.
- Broadcast: send one request per teammate so each response can be tracked independently.
- Direct teammate-to-teammate discussion is disabled by default; route through Codex lead unless an explicit VETO discussion round allows peer review.
