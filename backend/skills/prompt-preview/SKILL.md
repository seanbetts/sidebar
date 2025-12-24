---
name: prompt-preview
description: Generate the current system prompt output with injected variables for preview or debugging.
metadata:
  capabilities:
    reads: false
    writes: false
    network: false
    external_apis: false
---

# Prompt Preview Skill

Use this skill to generate the system prompt output exactly as it would be injected for the current user.

## When to use

- The user asks to view or verify the injected prompts.
- You need a reliable preview of the current prompt output after variables are resolved.

## Tool

Call the tool named **Generate Prompts**. It returns the generated prompt output.
