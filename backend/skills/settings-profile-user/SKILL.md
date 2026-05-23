---
name: settings-profile-user
description: Read and update user-managed profile details, personal context, communication preferences, and profile image. Use when the assistant needs to inspect or modify these settings.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Profile & Preferences Skill

Manage user-owned profile details and preference fields from the Profile and User sections.

## Tools

- `Get Profile and User Settings`
- `Update Profile and User Settings`
- `Upload Profile Image`
- `Remove Profile Image`

## Notes

- Text fields support partial updates.
- Passing an empty string clears a text field.
- Use `clear_date_of_birth` when the date should be removed.
