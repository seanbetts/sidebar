---
title: Subscription & Paywall
description: How sideBar presents subscription tiers, upgrade prompts, message caps, and billing management across all platforms.
---

## Purpose

Define how sideBar communicates subscription state, presents upgrade paths, enforces usage limits, and manages billing. Subscription boundaries should feel like natural product edges, not errors or punishments. The goal is for free users to see the value of AI and for capped users to understand their options, without friction that feels hostile.

---

## Design principles

- **Boundaries, not barriers.** A message cap or feature gate is a product boundary. It is not an error. Do not use error surfaces (toasts, alerts, red text) for subscription states.
- **Specific and actionable.** Every upgrade prompt tells the user exactly what they can't do, what tier unlocks it, and how to upgrade. No vague "upgrade for more" language.
- **Quiet until relevant.** Subscription state is invisible when the user is within their tier. It surfaces only at the moment a boundary is reached or a gated feature is tapped.
- **Consistent across platforms.** The same tiers, prices, and gating rules apply on iOS, macOS, and web. Only the payment mechanism differs (StoreKit vs Stripe).

---

## Tier model

| Tier | Price | AI access | Message cap | Skills |
|---|---|---|---|---|
| Free | $0 | None | N/A | Browse Store only |
| Plus | $8/mo \| $80/yr | Bundled | 30/day | Standard + basic Store |
| Pro | $15/mo \| $150/yr | Bundled | 150/day | Full Store including flagship |
| BYOK | $5/mo \| $50/yr | Own key | None | Full Store including flagship |

Beta and admin roles bypass all gating. The role check happens before any subscription check.

---

## Tier badge component

A compact label used on skill cards, the Skills Store, settings, and upgrade prompts to indicate which tier unlocks a feature.

| Property | Value |
|---|---|
| Shape | Capsule (pill) |
| Typography | `.caption`, `.fontWeight(.medium)` |
| Variants | `plus`, `pro` (free and BYOK do not need badges in UI) |
| Colors | Use `surface` fill with `textPrimary` foreground. No accent colours. Adapts to light/dark mode. |
| Accessibility | `.accessibilityLabel("Requires [tier name] subscription")` |

Tier badges appear:

- On skill cards in the Skills Store for skills the user's current tier cannot access
- In Settings > Skills next to gated skills
- In upgrade prompts to identify which tier is needed

Badges are hidden for skills the user already has access to. They are informational for browsing, not persistent labels on unlocked content.

---

## Subscription-gated surfaces

### Chat (free users)

Free users see the full chat interface but cannot send messages. The input area is replaced with a subscription prompt:

- Input field is visible but disabled (greyed out, not interactive)
- Below the input area, a compact prompt card appears:
  - Text: "Subscribe to chat with sideBar" (engaged register)
  - Two action buttons: "See plans" (primary, routes to subscription management) and "Bring your own key" (secondary, routes to BYOK setup)
- Existing conversations (if any from a lapsed subscription) remain readable but not continuable

The chat conversation list remains fully accessible. Past conversations are cached and readable offline as with any other tier.

### Chat (message cap reached)

When a Plus or Pro user exhausts their daily message cap:

- The input field is disabled with a brief inline message: "You've used all [N] messages for today"
- A reset time is shown: "Resets at midnight" (in the user's local timezone)
- For Plus users only, an upgrade prompt appears: "Upgrade to Pro for 150 messages a day" with a "See plans" action
- Pro users see only the reset time, no upgrade prompt (they are on the highest bundled tier)
- The cap counter is visible in the chat header area once the user reaches 80% of their daily limit, showing remaining messages (e.g., "6 messages left today"). Below 80%, nothing is shown.

**Cap reset:** midnight in the user's local timezone. The backend tracks the user's timezone from the device context sent with each message.

**Cap counting:** each user message that triggers an assistant response counts as one message. Retries of failed messages do not count again. Skill executions within a single response do not add to the count.

### Skills Store (free users)

Free users can browse the full Skills Store. Each skill card shows:

- The skill's name, description, and category as normal
- A tier badge indicating which subscription unlocks it ("Plus" or "Pro")
- Tapping a skill opens its detail view with full description and a subscription prompt at the bottom instead of an "Install" button: "Subscribe to install skills" with a "See plans" action

### Skills Store (Plus users viewing flagship skills)

Plus users see flagship skills with a "Pro" tier badge. Tapping opens the detail view with: "Upgrade to Pro to install this skill" and a "See plans" action. Basic Store skills show the normal "Install" button.

### Settings > Skills (gated skills)

Skills the user's tier cannot access appear in the list but with a tier badge and a disabled toggle. Tapping the row opens the skill detail with the appropriate upgrade prompt.

---

## Upgrade prompts

Upgrade prompts are contextual and appear inline where the boundary is encountered. They are never modals, never alerts, and never interruptive.

### Anatomy

Every upgrade prompt contains:

- **What's blocked**: a specific, plain-language description of what the user tried to do
- **What unlocks it**: the tier name (with badge)
- **Action**: a "See plans" button that routes to subscription management

### Copy guidance

Use the engaged register. Be warm, specific, and honest.

**Do**:
- "You've used all 30 messages for today. Upgrade to Pro for 150 a day, or check back tomorrow."
- "Deep research needs a Pro subscription."
- "Subscribe to chat with sideBar"

**Don't**:
- "Upgrade for more!" (vague)
- "You've hit your limit" (feels punitive without context)
- "Premium feature" (avoid the word "premium"; use the tier name)

### Placement

| Context | Placement |
|---|---|
| Chat input (free user) | Below disabled input field |
| Chat input (cap reached) | Below disabled input field |
| Skill card (gated) | Bottom of skill detail view |
| Skill toggle (gated) | Inline in settings row |

---

## Subscription management

### In Settings

A new **Subscription** section in Settings shows the user's current plan and billing state.

| Element | Content |
|---|---|
| Current plan | Tier name and badge, billing period (monthly/annual) |
| Price | Current price with billing frequency |
| Billing platform | "Managed by Apple" or "Managed on web" with appropriate guidance |
| Next renewal | Date of next charge |
| Actions | "Change plan" (routes to plan picker), "Cancel" (routes to platform-specific cancellation) |

**Apple subscribers:** "Cancel" links to the App Store subscription management deep link (`itms-apps://apps.apple.com/account/subscriptions`). sideBar cannot cancel Apple subscriptions directly.

**Web subscribers:** "Cancel" initiates cancellation through the sideBar website/Stripe customer portal.

**Cross-platform note:** if a user subscribed on one platform and views Settings on another, show the billing platform and direct them there for changes. Do not attempt to manage a Stripe subscription from the iOS app or vice versa.

### Plan picker

The plan picker is presented as a sheet (`.sheet` on iOS/macOS, modal on web) showing all available tiers in a comparison layout:

- Each tier as a card: name, price (monthly and annual toggle), key features listed
- Current plan highlighted
- "Subscribe" / "Change plan" / "Downgrade" button per card, contextual to the user's current tier
- BYOK card includes a note: "Bring your own API key" and links to the API keys setup page

Annual vs monthly toggle at the top of the picker. Default to annual (better value).

### Downgrade behaviour

When a user downgrades (e.g., Pro to Plus, or any tier to Free):

- Access continues until the end of the current billing period
- After the period ends, feature access adjusts to the new tier
- No data is deleted. Notes, tasks, websites, files, and conversation history are fully retained on all tiers.
- Skills that are no longer available on the new tier are disabled but not uninstalled. If the user re-upgrades, they are re-enabled without needing to reinstall.

---

## Presentation model

| Platform | Plan picker | Subscription management |
|---|---|---|
| iPhone | `.sheet` (full screen cover) | Settings > Subscription |
| iPad | `.sheet` (standard) | Settings > Subscription |
| macOS | `.sheet` (standard) | Settings > Subscription |
| Web | Modal overlay | Settings > Subscription (Stripe customer portal for billing) |

---

## Onboarding integration

The subscription choice is introduced during onboarding (see [Onboarding](./onboarding) Steps 5-6). Users who skip subscription setup land on the free tier with a persistent recovery path in Chat and Settings.

---

## Rules summary

1. **Subscription boundaries are not errors.** Never use error presentation surfaces (toasts, alerts, red text, PlaceholderView) for subscription state. Use the upgrade prompt pattern.
2. **Upgrade prompts are contextual and inline.** They appear where the boundary is encountered, never as modals or interstitials.
3. **Tier badges appear only on gated content.** Do not badge content the user already has access to.
4. **Cap counter appears at 80% usage.** Below 80%, subscription state is invisible in the chat UI.
5. **Downgrade preserves all data.** No content is deleted or hidden when a user downgrades. Skills are disabled, not uninstalled.
6. **Cross-platform billing is transparent.** Always tell the user which platform manages their subscription and route them there for changes.
7. **Beta and admin bypass all gating.** The role check happens before any subscription check. These users never see upgrade prompts or tier badges.
8. **"See plans" is the universal upgrade action.** All upgrade prompts route to the same plan picker. Do not create multiple entry points to different upgrade flows.
9. **No "premium" language.** Use tier names (Plus, Pro) not generic labels.
10. **Engaged register for all subscription copy.** Warm, specific, actionable. See [Voice and Content](../voice-and-content) for full guidance.

---

## Related docs

- [Onboarding](./onboarding)
- [AI Assistant UI](./ai-assistant-ui)
- [Error Presentation](./error-presentation)
- [Navigation](./navigation)
- [Voice and Content](../voice-and-content)
- [Empty State](../components/empty-state)
