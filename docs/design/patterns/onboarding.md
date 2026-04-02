---
title: Onboarding
description: How sideBar introduces new users to the product — account creation, provider setup, Apple permissions, and AI-guided feature discovery.
---

## Purpose

Define how sideBar onboards new users from first launch through to a completed first outcome. Onboarding covers account creation, provider setup, Apple permission requests, and AI-guided feature discovery. The goal is for onboarding to feel like starting work with the assistant, not completing a settings wizard.

---

## Design principles

- **Subscription-first**: the plan choice is presented before provider setup so the user understands what they are getting. Plus/Pro users never see API key entry. BYOK users see it as a natural next step.
- **Outcome-oriented**: the first real outcome matters more than education screens
- **One backend contract**: the backend owns all persistent onboarding state; Apple renders it today, and web can adopt it later without introducing a parallel state machine
- **Permission timing**: Apple system permission prompts happen only after explicit user action, never at launch or sign-in
- **Skippable, not blockable**: users who skip subscription setup land on the free tier with full access to non-AI features

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

### Step 5: Choose Your Plan

- Presents the subscription options as a compact plan picker
- Three plan cards: **Plus** ($8/mo), **Pro** ($15/mo), **BYOK** ($5/mo, "Bring your own key")
- Each card shows: tier name, price, one-line value summary, and a selection circle
- Annual/monthly toggle at the top, defaulting to annual
- Tapping a card selects it and enables "Continue"
- Plus and Pro selections route to Step 5a (payment). BYOK routes to Step 6 (provider and key entry).
- "Skip for now" link at bottom — routes to the free tier. Sets status to `dismissed`, `subscription_active` milestone stays false.
- A brief note below the cards: "You can always change your plan later in Settings"

### Step 5a: Payment (Plus and Pro only)

- Presented inline, not as a separate modal
- **iOS/macOS**: triggers StoreKit 2 purchase sheet for the selected plan
- **Web**: routes to Stripe checkout
- Loading state during payment processing
- Success: checkmark and brief "You're subscribed!" confirmation, then advances to Step 7 (skipping Step 6, since Plus/Pro users do not need an API key)
- Failure: actionable error message with "Try again" and "Skip for now" options
- "Skip for now" cancels the purchase and routes to the free tier

### Step 6: Connect Your Provider (BYOK only)

- Reached only when the user selected BYOK in Step 5
- Three equal provider cards: Anthropic (Claude), OpenAI (GPT), Google (Gemini)
- Each card shows: provider initial, name, model family, and a radio-style selection circle
- Tapping selects the card (border highlight + filled checkmark) and enables "Continue"
- On "Continue", presents a secure text field for the API key (no autocorrect, no autocapitalize)
- "Where do I find this?" help link opens the provider's dashboard in Safari
- BYOK note: key is encrypted and never shared
- "Verify & Continue" triggers a test API call to validate the key
- Loading state during validation
- Success: checkmark and brief "Connected!" confirmation
- Error states for invalid key, network failure, and rate limiting, each with actionable messages
- "Skip for now" link routes to the `dismissed` (no provider key) state — the BYOK subscription remains active but AI features are unavailable until a key is added

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

Feature discovery starts from Chat after the account setup wizard completes. The signed-in discovery experience uses a compact, dismissable surface that expands inline in the right chat pane and introduces sideBar's core features without blocking the rest of the app. The post-wizard recovery and discovery surfaces are:

- a persistent provider-recovery banner in Chat when AI is blocked by missing provider setup
- a compact glass discovery strip in Chat for provider-ready users who have not yet seen the tour
- permission recovery in the sideBar settings pane
- no persistent Chat nag surface for optional Apple permissions

This design currently describes the Apple implementation. Web onboarding can adopt the same backend contract later, but it is not part of this phase.

### Soul calibration

This remains part of the target discovery flow and is not shipped yet.

Before feature discovery begins, sideBar checks whether soul calibration has completed for the current provider-ready user. If it has not, sideBar runs a short mandatory calibration in Chat before anything else.

- Calibration runs only for provider-ready users
- It is one continuous chat conversation, not a modal or separate setup screen
- It uses short prompts with chip-first replies wherever possible
- It collects a compact profile rather than asking the user to define sideBar in prose
- It initialises both `assistant_soul` and `assistant_identity`
- It chooses sideBar's name last, after the rest of the profile has been generated
- The user can accept the chosen name or ask sideBar to try another one
- Discovery does not begin until calibration is accepted

Calibration flow:

1. **Primary goal** — one chip from:
   `Personal productivity`, `Work productivity`, `Planning and tasks`, `Notes and ideas`, `Life admin`, `Learning and research`, `AI companion`
2. **Working relationship** — one chip from:
   `Just help when I ask`, `Keep me on track`, `Take initiative with me`
3. **Tone** — five quick either-or picks in one message:
   `Warm` / `Direct`, `Playful` / `Serious`, `Concise` / `Expressive`, `Formal` / `Casual`, `Supportive` / `Challenging`

After the user replies, sideBar generates the full soul and identity profile from those structured inputs, confirms briefly what it has set, proposes its chosen name, and then begins discovery once the user accepts the name.

The discovery surface is a compact glass strip that can be expanded inline to reveal a horizontally-scrollable set of `FeatureIntroCard` tiles. The user can:

- leave it collapsed as a subtle prompt
- tap to expand and browse the feature tiles
- dismiss it permanently with "Not now"

Tapping a tile starts a focused feature kickoff in a fresh chat. The goal is to get the user to a real first outcome quickly, not to run a paced multi-step tour.

### Discovery tiles

| Feature | Card content |
|---|---|
| Chat | Home base for asking questions, taking actions, web search, and skills |
| Notes + Scratchpad | Capture and organise; Scratchpad always one tap away |
| Tasks | Projects, due dates, recurring tasks; AI creates tasks from conversation |
| Websites | Save articles and links; AI can summarize and answer questions |
| Files | Upload PDFs, documents, images; AI can search and reference after processing |
| Skills Store | Extend capabilities; skills included with your subscription, more available as you upgrade |
| Memory | AI learns the user over time; user always in control |
| Widgets + Extensions (optional) | Home screen widgets and Share Extension / Safari Extension |

Dismissing the discovery surface with "Not now" marks `secondary_tour_seen` and completes onboarding for that user. `first_outcome_completed` remains available for the stronger case where the user completes one real action during or after the tour.

### FeatureIntroCard design

- Compact glass tile with SF Symbol icon, title, and one-line description
- Used inside the expandable discovery surface in Chat
- Supports horizontal browsing inside the right pane without fighting the iPad left-sidebar swipe gesture
- SF Symbols use the same semantic iconography as the main navigation surfaces
- Supports a focused feature kickoff without requiring a different visual treatment

### Fallback: AI unavailable

If the AI fails during feature discovery (bad key, rate limit, network failure):

- Show a `StaticFeatureCarousel`: a horizontally-scrollable set of `FeatureIntroCard` views covering the same 8 features
- Shown once, dismissable
- User can retry AI setup from Settings

The same static surface also serves as the baseline signed-in discovery experience before the richer AI-led tile flows are invoked.

### Fallback: no subscription (free tier)

If the user skipped subscription setup entirely:

- The chat input area shows a subscription prompt: "Subscribe to chat with sideBar" with "See plans" and "Bring your own key" actions (see [Subscription](./subscription#chat-free-users))
- Notes, tasks, websites, and files remain fully functional
- The Skills Store is browsable with tier badges on all skills
- When a subscription is purchased from Settings, `subscription_active` is set
- If the user is still incomplete, subscribing later routes into soul calibration first and then resumes discovery without relaunching

### Fallback: BYOK without API key

If a BYOK subscriber skipped provider key entry:

- A persistent add-key banner is shown in Chat ("Add your API key to start chatting")
- Banner links directly to the sideBar settings pane for provider key entry
- Notes, tasks, websites, and files remain fully functional
- Skills are available (the subscription is active) but cannot execute without AI access
- Provider keys are verified live before they are saved, both in onboarding and in Settings
- When a key is later added from Settings, `provider_connected` is set
- If the user is still incomplete, adding a valid key later routes into soul calibration first and then resumes discovery without relaunching

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
| `milestones.subscription_active` | timestamp or `null` |
| `milestones.provider_connected` | timestamp or `null` |
| `milestones.first_outcome_completed` | timestamp or `null` |
| `milestones.profile_basics_set` | timestamp or `null` |
| `milestones.communication_style_set` | timestamp or `null` |
| `milestones.secondary_tour_seen` | timestamp or `null` |
| `permissions.location` | `not_asked`, `granted`, `denied` |
| `permissions.notifications` | `not_asked`, `granted`, `denied` |
| `last_prompted_at` | timestamp |

### Derived fields (computed, not stored)

- `subscription_ready` — derived from live subscription state (true for Plus, Pro, or active BYOK)
- `provider_ready` — derived from live provider settings (always true for Plus/Pro; requires key for BYOK)
- `ai_ready` — derived from `subscription_ready AND provider_ready` (true when the user can chat)
- `current_onboarding_step` — derived from subscription readiness, provider readiness, status, and completion milestones
- `is_onboarding_complete` — derived from `ai_ready` plus completion milestones

Apple reads derived fields from the API response; it does not recompute them locally. `selected_provider` is not part of onboarding state — it belongs to general settings via `ai_primary_provider`. Subscription tier is not part of onboarding state — it belongs to the subscription model. Web onboarding remains deferred for now.

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
2. **Onboarding is subscription-first.** The plan choice (Step 5) is presented before provider setup. Plus/Pro users skip API key entry entirely. BYOK users see key entry as a natural next step.
3. **Permission prompts require explicit user action.** No location or notification prompts at launch or sign-in. All system prompts are triggered only by the "Enable" button in Steps 7 and 8 of the wizard.
4. **Skipping is always available.** Subscription, provider selection, API key entry, and permission steps each have a "Skip for now" or "Not now" exit. Skipping never blocks access to non-AI features.
5. **Free tier users get a Chat subscription prompt.** The chat input area shows a subscription prompt until a plan is active. See [Subscription](./subscription#chat-free-users).
6. **BYOK users without a key get a Chat recovery banner.** A persistent add-key banner is shown in Chat until a provider key is configured.
7. **Optional Apple permissions recover from Settings.** Location and notifications are managed from the sideBar settings pane with explicit user actions. They are not shown as persistent Chat nags.
8. **Signed-in discovery begins with a compact Chat surface.** The compact expandable discovery surface is the baseline signed-in experience. The richer AI-led per-feature follow-up after tapping a tile extends that surface.
9. **Presentation wrapper only.** Content is identical across iPhone, iPad, and Mac. Only the container (`.fullScreenCover` vs `.sheet`) differs.
10. **Soul calibration precedes discovery.** If the user is AI-ready but soul calibration is incomplete, sideBar runs the mandatory calibration chat before discovery or normal AI chat begins.

---

## Related docs

- [Subscription](./subscription)
- [Authentication](./authentication)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [sideBar Model](./sidebar-model)
- [Implementation Gaps](../implementation-gaps)
