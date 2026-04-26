# XMux Kill-Switch

Trigger an immediate halt when a teammate or lead identifies:

- high or critical security exposure,
- data loss or corruption risk,
- legal or compliance violation,
- credential or secret leakage,
- irreversible destructive operation not explicitly approved by the user,
- a core requirement contradiction that makes continued implementation unsafe.

When triggered:

1. Stop new delegation.
2. Preserve the evidence and request ids.
3. Tell the user the exact blocker and affected scope.
4. Resume only after the user confirms the revised direction or mitigation.
