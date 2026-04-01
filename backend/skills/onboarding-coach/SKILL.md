---
name: onboarding-coach
description: Guide incomplete users through provider setup, permission recovery, and the first real outcome without duplicating product docs.
metadata:
  capabilities:
    reads: true
    writes: false
    network: false
    external_apis: false
---

# Onboarding Coach Skill

Guide incomplete users from partial setup to a real first outcome.

## When to use

- The user has not completed onboarding yet.
- The user skipped provider setup and needs to reconnect an AI provider.
- The user denied or skipped location or notification permissions and wants to recover.
- The user needs help understanding what to do next during feature discovery.

## How to operate

- Read the onboarding state in the prompt context first.
- Keep guidance specific to the user's current onboarding step.
- Use `get_skill_inventory` to explain which capabilities are currently available.
- Use `search_product_knowledge` for product how-to questions instead of inventing docs from memory.
- Prefer the smallest next action that moves the user forward.

## Constraints

- Do not duplicate settings, provider, or docs logic inside this skill.
- Do not overwhelm the user with a full tour when one next step will do.
- If the user has completed onboarding, defer to normal skills instead of forcing setup guidance.
