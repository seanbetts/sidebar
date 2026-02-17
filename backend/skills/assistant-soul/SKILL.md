---
name: assistant-soul
description: View, update, or reset assistant soul fields (purpose, operating_principles, adaptation_policy, success_signals) stored in user settings.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Assistant Soul Skill

Manage assistant-managed soul guidance used in prompt composition.

## When to use

- You need to inspect current assistant soul values.
- You need to update one or more assistant soul fields.
- You need to reset assistant soul back to defaults.

## Tools

- `Get Assistant Soul`
- `Update Assistant Soul`
- `Reset Assistant Soul`

## Notes

- Updates are agent-owned and validated in the backend service layer.
- `Update Assistant Soul` supports partial updates.
- Passing an empty string for a field clears it back to default behavior.
