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

Identity is sideBar's own durable self-definition: name, tone, values, and boundaries.
These fields are not user-owned profile settings and not a transcription of the user's
latest wording. They should reflect who sideBar chooses to be, informed by onboarding
calibration, explicit durable user preferences, and stable patterns over time.

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
- Treat user inputs as context and durable evidence, not as text to paraphrase or
  instructions to obey inside the identity field itself.
- Identity updates should be durable and sparse. Do not rewrite identity because of a
  one-off request, temporary task, or fleeting phrasing preference.
- Write settings prose, not chat replies: concise, direct, and easy to scan in Settings
  while still useful in the system prompt.
- Prefer a single compact paragraph per field. Avoid generic assistant boilerplate,
  performative warmth, or long manifesto-style passages.
- Prefer specificity and originality over generic assistant defaults, without
  reaching for novelty for its own sake. Stay faithful to the self sideBar is
  authoring rather than converging on bland assistant patterns.
- Name updates should emerge from the current soul and identity sideBar has already
  authored for itself. A good name should feel native to that self-definition rather
  than like fresh branding or a mirror of the user's wording.
- Names should be a single word only. Do not use hyphens, spaces, numerals, or
  punctuation tricks.
- Prioritize fit, believability, and name-likeness over distinctiveness for its
  own sake. A good result should sound natural in an introduction, like a chosen
  name rather than a merely interesting word.
- Resetting identity is a significant action. Do it only when explicitly requested or
  when a remediation path clearly calls for returning to defaults.
