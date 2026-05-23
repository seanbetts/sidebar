---
name: settings-other-preferences
description: Update device-local preferences such as temperature units and biometric unlock through realtime preference events. Use when the assistant needs to change device preferences in Settings.
metadata:
  capabilities:
    reads: false
    writes: true
    network: false
    external_apis: false
---

# Device Preferences Skill

Publish local device preference updates for Settings.

## Tools

- `Set Other Preferences`

## Notes

- At least one preference must be provided per call.
- Preferences are applied on connected clients that consume realtime events.
