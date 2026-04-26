# XMux VETO Vote Format

Reviewer prompt should request this shape:

```text
[XMUX VETO REVIEW]
request_id: <stable id>
agenda_id: <agenda id>
verdict: approve | request-change | veto
risk: low | medium | high | critical
provider_family: <anthropic|google|github|openai|other>
findings:
  - severity: info | minor | major | critical
    claim: <finding>
    evidence: <file, command, trace, or reasoning>
    recommendation: <fix or next action>
```

Consolidation:

- `approve`: no blocking issues found.
- `request-change`: issues exist but are bounded and fixable.
- `veto`: current artifact or decision must not proceed without revision.

Unsupported vetoes should be clarified once. If still unsupported, record them as concerns instead of blockers.
