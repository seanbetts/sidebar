---
name: settings-other-preferences
description: Update device-local Other settings preferences (temperature units and biometric unlock preference) through realtime preference events. Use when the assistant needs to change settings in the Other section.
metadata:
  capabilities:
    reads: false
    writes: true
    network: false
    external_apis: false
---

# Settings Other Preferences Skill

Publish local preference updates for the Other settings section.

## Tools

- `Set Other Preferences`

## Notes

- At least one preference must be provided per call.
- Preferences are applied on connected clients that consume realtime events.
