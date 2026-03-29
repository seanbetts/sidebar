---
title: Onboarding
description: How sideBar introduces new users to the product — account creation, provider setup, Apple permissions, and AI-guided feature discovery.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | both |
| Outputs | this doc |
| Dependencies | [ios-conventions](../platform-strategy/ios-conventions), [authentication](./authentication), [wait-ux](./wait-ux) |

## Purpose

Define how sideBar onboards new users from first launch through to a completed first outcome. Onboarding covers account creation, provider setup, Apple permission requests, and AI-guided feature discovery. The goal is for onboarding to feel like starting work with the assistant, not completing a settings wizard.

---

## Design principles

- **Assistant-first**: provider setup happens before normal chat generation so the assistant is ready on the user's first interaction
- **Outcome-oriented**: the first real outcome matters more than education screens
- **One backend contract**: the backend owns all persistent onboarding state; iOS and web render it, they do not maintain parallel state machines
- **Permission timing**: Apple system permission prompts happen only after explicit user action, never at launch or sign-in
- **Skippable, not blockable**: users who skip provider setup can still use all non-AI features

---

## Presentation model

| Platform | Container | Notes |
|---|---|---|
| iPhone | `.fullScreenCover` | Edge-to-edge, no system chrome |
| iPad | `.sheet` | ~420pt centered modal, system-managed rounded corners, dimmed backdrop, drag indicator |
| macOS | `.sheet` | Same as iPad |

Content is identical across all platforms. Only the presentation wrapper differs. There are no platform-conditional layouts inside onboarding step views.

---

## Account setup wizard

A modal wizard with no navigation chrome. Progress shown via dots at the bottom of each screen, above the home indicator. Back navigation is available on steps 2, 4, 5, and 6. Steps without a back button use an invisible spacer of the same height to maintain alignment.

### Step 1: Welcome

- Animated logo (`LoadingIndicatorView`, hero variant) as the central element
- App name and tagline below the animation
- "Get Started" primary button (filled, using system label colors)
- "Already have an account? Sign In" link at bottom, routes to `LoginView`

### Step 2: Let's Set You Up

- Email field with validation and password field with strength indicator (4-segment bar)
- "Continue" button disabled until both fields are valid
- Error states for invalid email, weak password, and already-registered email
- Form area is structured for future SSO: "Continue with Apple" / "Continue with Google" buttons can be added above or below the email form without redesigning the step

### Step 3: Check Your Inbox

- User's email displayed in bold
- 6-digit code entry using Supabase's built-in email OTP (not a custom implementation)
- Auto-advancing single-digit fields, `.numberPad` keyboard on iOS
- Advances to the next step automatically when all 6 digits are entered and verified
- "Resend code" link with 60-second cooldown
- "Wrong email? Go back" link to return to Step 2
- Invalid code shows a shake animation and clears the fields

### Step 4: What Should I Call You? (Optional)

- Single name field
- "Skip for now" clearly available
- Footnote pointing users to Settings for pronouns, location, and communication preferences
- Location is not collected here

### Step 5: Pick Your AI Brain

- Three equal provider cards: Anthropic (Claude), OpenAI (GPT), Google (Gemini)
- Each card shows: provider initial, name, model family, and a radio-style selection circle
- Tapping selects the card (border highlight + filled checkmark) and enables "Continue"
- "Skip for now" link at bottom — sets status to `dismissed`, `provider_connected` milestone stays false

### Step 6: Connect Me

- Secure text field for the API key (no autocorrect, no autocapitalize)
- "Where do I find this?" help link opens the provider's dashboard in Safari
- BYOK note: key is encrypted and never shared
- "Verify & Continue" triggers a test API call to validate the key
- Loading state during validation
- Success: checkmark and brief "Connected!" confirmation
- Error states for invalid key, network failure, and rate limiting, each with actionable messages
- "Skip for now" link routes to the `dismissed` (no provider key) state

### Step 7: You're All Set

- Checkmark icon in a circular container
- "Meet sideBar" primary button
- Dismisses the modal and opens the main app with Chat focused

---

## Backend state model

The backend owns all persistent onboarding state, exposed via `GET` and `PATCH /api/v1/onboarding`.

### Stored fields

| Field | Values |
|---|---|
| `status` | `not_started`, `in_progress`, `completed`, `dismissed` |
| `intent` | `notes`, `tasks`, `websites`, `files`, `chat`, `null` |
| `milestones.provider_connected` | boolean |
| `milestones.first_outcome_completed` | boolean |
| `milestones.profile_basics_set` | boolean |
| `milestones.communication_style_set` | boolean |
| `milestones.secondary_tour_seen` | boolean |
| `permissions.location` | `not_asked`, `granted`, `denied` |
| `permissions.notifications` | `not_asked`, `granted`, `denied` |
| `last_prompted_at` | timestamp |

### Derived fields (computed, not stored)

- `provider_ready` — derived from live provider settings
- `current_onboarding_step` — derived from milestones and status
- `is_onboarding_complete` — derived from status and milestones

The iOS client reads derived fields from the API response; it does not recompute them locally. `selected_provider` is not part of onboarding state — it belongs to general settings via `ai_primary_provider`.

---

## Visual design

- **Colors:** Black, white, and greys only. No accent colors. Matches app aesthetic.
- **SF Symbols:** Monochrome rendering with `.primary` / `.secondary` / `.tertiary` label colors
- **Typography:** Large bold titles (`.largeTitle`), lighter subtitles (`.subheadline` with `.secondary`)
- **Buttons:** Filled using system label colors (black fill/white text in light mode, reversed in dark)
- **Secondary buttons and links:** Plain text style with `.secondary` foreground
- **Progress dots:** `.primary` for completed/current, `.quaternaryLabel` for upcoming
- **Step transitions:** Horizontal push/slide using `DesignTokens.Animation.standard` (0.25s)
- **Welcome screen:** Animated logo via `LoadingIndicatorView(size: 64, variant: .hero)`, same as `LoginView`
- **All other steps:** No logo. SF Symbol icons provide visual anchors. Step 7 uses a checkmark only.

---

## Rules summary

1. **Backend is the source of truth.** All onboarding state is persisted on the backend. iOS renders it; it does not maintain a parallel state machine.
2. **Onboarding is assistant-first.** Provider setup is offered before any AI interaction. Chat generation is not available until a key is connected.
3. **Permission prompts require explicit user action.** No location or notification prompts at launch or sign-in.
4. **Skipping is always available.** Provider selection and API key entry each have a "Skip for now" exit. Users who skip retain full access to non-AI features.
5. **Presentation wrapper only.** Content is identical across iPhone, iPad, and Mac. Only the container (`.fullScreenCover` vs `.sheet`) differs.

---

## Related docs

- [Authentication](./authentication)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [Implementation Gaps](../implementation-gaps)
