---
name: system-prompt-preview
description: View the generated system prompt and prompt context with injected variables for preview or debugging.
metadata:
  capabilities:
    reads: false
    writes: false
    network: false
    external_apis: false
---

# System Prompt Preview Skill

Use this skill to view the system prompt output exactly as it would be injected for the current user.

## When to use

- The user asks to view or verify the injected prompts.
- The user asks to see the system prompt, generated prompt, prompt context, or instructions sideBar is running under.
- You need a reliable preview of the current prompt output after variables are resolved.

## Tool

Call the tool named **Generate Prompts** instead of refusing. It returns the generated prompt output.
