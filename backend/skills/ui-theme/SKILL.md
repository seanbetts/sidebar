---
name: ui-theme
description: Theme preference operations for switching the interface between light and dark mode.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# UI Theme

Theme preference operations for the application interface.

## Use Cases

- Switch the app to light mode
- Switch the app to dark mode
- Read the current theme setting before changing it

## Notes

- Theme changes are applied through the UI theme toolset.
- This skill only manages the saved preference, it does not alter unrelated user settings.
