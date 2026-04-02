---
title: Onboarding
description: How sideBar introduces new users to the product — account creation, provider setup, Apple permissions, and AI-guided feature discovery.
---

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

A modal wizard with no navigation chrome. Progress shown via dots at the bottom of each screen, above the home indicator. Back navigation is available on steps 2, 4, 5, 6, 7, and 8. Steps without a back button use an invisible spacer of the same height to maintain alignment.

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

### Step 7: Share Your Location (Optional)

- Explains product value: location enables weather, local recommendations, and time-aware responses
- "Enable" triggers the system location prompt
- "Not now" skips without prompting — advances to Step 8
- Outcome written to backend: `permissions.location`

### Step 8: Stay in the Loop (Optional)

- Explains product value: task reminders, file completion, and assistant attention
- "Enable" triggers the system notifications prompt
- "Not now" skips without prompting — advances to Step 9
- Outcome written to backend: `permissions.notifications`

### Step 9: You're All Set

- Checkmark icon in a circular container
- "Meet sideBar" primary button
- Dismisses the modal and opens the main app with Chat focused

---

## Feature discovery

The intended end state is an AI-guided feature tour from Chat after the account setup wizard completes. The backend now detects incomplete onboarding and injects onboarding context into the system prompt, but the full Phase 2 discovery surface is still pending. Today, the shipped post-wizard recovery surfaces are:

- a persistent provider-recovery banner in Chat when AI is blocked by missing provider setup
- permission recovery in the sideBar settings pane
- no persistent Chat nag surface for optional Apple permissions

### Soul calibration

This remains part of the target discovery flow and is not shipped yet.

Before the feature tour begins, the assistant checks whether `assistant_soul` has been initialised. If it has not, the assistant runs a brief calibration before anything else.

- The assistant asks up to three concise conversational questions to understand the user's context, goals, and working style
- Questions are plain and natural — not a form
- After the user answers, the assistant initialises both `assistant_soul` and `assistant_identity` from the answers and confirms briefly what it has set
- The feature tour then begins immediately after calibration completes
- If the user skips or declines to answer, the assistant initialises from defaults and proceeds

Calibration must complete before the feature tour. The assistant does not proceed to the tour with an uninitialised soul.

In the planned Phase 2 experience, the AI greets the user by name (if provided in Step 4) and begins the tour. For each feature, a `FeatureIntroCard` appears inline in the chat view. The AI waits for acknowledgment before advancing. Users can say "skip", "next", or "show me everything" to control pacing. A persistent "Skip Tour" option is always visible.

### Tour sequence

| Feature | Card content |
|---|---|
| Chat | Home base for asking questions, taking actions, web search, and skills |
| Notes + Scratchpad | Capture and organise; Scratchpad always one tap away |
| Tasks | Projects, due dates, recurring tasks; AI creates tasks from conversation |
| Websites | Save articles and links; AI can summarize and answer questions |
| Files | Upload PDFs, documents, images; AI can search and reference after processing |
| Skills Store | Extend capabilities; three tiers (Required, Standard, Store) |
| Memory | AI learns the user over time; user always in control |
| Widgets + Extensions (optional) | Home screen widgets and Share Extension / Safari Extension |

In the planned Phase 2 experience, the closing message marks onboarding complete via the backend API. `first_outcome_completed` is set when the user completes one real action during or after the tour.

### FeatureIntroCard design

- Monochrome card with SF Symbol icon, title, one-line description
- Dismiss (X) in top-right corner; optional "Try it" CTA button
- Appears inline between chat messages
- Slide-in / fade-out using `DesignTokens.Animation.standard` (0.25s)
- SF Symbols use `.primary` / `.secondary` label colors

### Fallback: AI unavailable

This fallback is still part of the planned Phase 2 discovery work.

If the AI fails during feature discovery (bad key, rate limit, network failure):

- Show a `StaticFeatureCarousel`: a horizontally-scrollable set of `FeatureIntroCard` views covering the same 8 features
- Shown once, dismissable
- User can retry AI setup from Settings

### Fallback: no API key

If the user skipped provider setup entirely:

- A persistent add-key banner is shown in Chat ("Chat needs an API key")
- Banner links directly to the sideBar settings pane for provider key entry
- Notes, tasks, websites, and files remain fully functional
- Chat shows an explanation that a key is needed for AI features
- When a key is later added from Settings, `provider_connected` is set
- Resuming discovery after a key is later added remains part of the pending Phase 2 flow

### Signed-in permission recovery

Optional Apple permissions are recovered from the sideBar settings pane, not from Chat.

- The `Permissions` section appears in sideBar settings when location or notifications are missing
- `Enable` is shown only when the permission is still `not_asked`
- `Open Settings` is shown when the permission was previously denied
- Granted permissions disappear from the recovery section because they can only be revoked from system Settings
- Permission recovery is independent of provider recovery in Settings, so users can manage optional permissions even while Chat is still blocked by missing BYOK setup

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
3. **Permission prompts require explicit user action.** No location or notification prompts at launch or sign-in. All system prompts are triggered only by the "Enable" button in Steps 7 and 8 of the wizard.
4. **Skipping is always available.** Provider selection, API key entry, and permission steps each have a "Skip for now" or "Not now" exit. Skipping never blocks access to non-AI features.
5. **Provider-dismissed users get a Chat recovery path.** A persistent add-key banner is shown in Chat until a provider and key are configured. Chat must explain why AI features are unavailable.
6. **Optional Apple permissions recover from Settings.** Location and notifications are managed from the sideBar settings pane with explicit user actions. They are not shown as persistent Chat nags.
7. **Feature discovery and its static fallback are still pending.** The eventual Phase 2 tour and `StaticFeatureCarousel` remain the target design, but they are not yet shipped.
8. **Presentation wrapper only.** Content is identical across iPhone, iPad, and Mac. Only the container (`.fullScreenCover` vs `.sheet`) differs.
9. **Soul calibration precedes the feature tour.** If `assistant_soul` is uninitialised, the assistant runs calibration before the tour begins. The tour does not start with a blank soul.

---

## Related docs

- [Authentication](./authentication)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [sideBar Model](./sidebar-model)
- [Implementation Gaps](../implementation-gaps)
