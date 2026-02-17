---
name: assistant-identity
description: View, update, or reset assistant identity fields (name, tone, values, boundaries) stored in user settings.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Assistant Identity Skill

Manage the assistant-managed identity profile used in prompt composition.

## When to use

- You need to inspect current assistant identity values.
- You need to update one or more identity fields.
- You need to reset identity back to defaults.

## Tools

- `Get Assistant Identity`
- `Update Assistant Identity`
- `Reset Assistant Identity`

## Notes

- Updates are agent-owned and validated in the backend service layer.
- `Update Assistant Identity` supports partial updates.
- Passing an empty string for a field clears it back to default behavior.
