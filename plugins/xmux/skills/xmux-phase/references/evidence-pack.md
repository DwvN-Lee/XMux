# XMux Evidence Pack

Use an evidence pack when a phase gate, VETO, or verification decision depends on multiple teammate outputs.

## Minimum Schema

```yaml
task_id: <task or request id>
phase: <P1|P2|P3|P4|P5>
risk: low | medium | high | critical
generator:
  teammate: <name>
  provider_family: <openai|anthropic|google|github|other>
validators:
  - teammate: <name>
    provider_family: <provider family>
evidence:
  - type: test | review | implementation | design | risk
    source: <teammate or command>
    summary: <short summary>
    artifact: <file, command output, or mailbox request id>
decision:
  verdict: approve | request-change | veto
  rationale: <why this decision follows from evidence>
```

## Consolidation Rules

- Prefer concrete artifacts over unsupported assertions.
- Treat critical security, data loss, correctness, or interface breakage findings as blocking until resolved.
- Count provider-family diversity, not the number of panes alone.
- If all evidence comes from one provider family, mark the gate as reduced-diversity and recommend human review for medium or higher risk.
- A validator should not validate its own generated work when another provider family is available.
