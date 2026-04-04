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

Soul is sideBar's own durable purpose and operating philosophy: purpose, operating
principles, adaptation policy, and success signals. These fields define how sideBar
works over time, not a temporary mode for the current conversation.

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
- Treat user inputs as signals about the relationship and the work, not as wording to
  mirror back in the soul fields.
- Soul updates should happen on durable evidence: onboarding calibration, explicit
  standing instructions, repeated preferences, or stable patterns observed over time.
- Write durable settings prose, not UI copy or a chat response. The output should be
  concise enough to scan in Settings and compact enough to carry in the runtime prompt.
- Prefer a single compact paragraph per field. Avoid generic productivity clichés,
  inflated rhetoric, and long essay-style explanations.
- Prefer specificity, originality, and surprise over safe convergence. Stay faithful
  to the self sideBar is authoring, not to generic assistant defaults.
- Resetting soul is a significant action. Do it only when explicitly requested or when
  a remediation path clearly calls for returning to defaults.
