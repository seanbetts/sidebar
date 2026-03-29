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

## Phases

| Phase | Name | Trigger |
|---|---|---|
| 1 | Account setup wizard | First launch (auth state `signedOut`, onboarding `not_started`) |
| 1.5 | Apple permission cards | After provider is confirmed, before AI tour |
| 2 | AI-guided feature discovery | After Phase 1 dismisses; AI drives from chat |

---

## Presentation model

| Platform | Container | Notes |
|---|---|---|
| iPhone | `.fullScreenCover` | Edge-to-edge, no system chrome |
| iPad | `.sheet` | ~420pt centered modal, system-managed rounded corners, dimmed backdrop, drag indicator |
| macOS | `.sheet` | Same as iPad |

Content is identical across all platforms. Only the presentation wrapper differs. There are no platform-conditional layouts inside onboarding step views.

---

## Phase 1: Account setup wizard

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
- Location is not collected here — handled separately in Phase 1.5

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

## ContentView routing

```
switch (authState, onboardingStatus, providerConnected) {
case (.signedOut, .notStarted, _):
    OnboardingView()           // Phase 1 wizard
case (.signedOut, _, _):
    LoginView()                // Returning user
case (.active, .inProgress, _):
    MainAppView()              // Phase 2: AI tour in chat
      .withFeatureTour()
      .withPermissionCards()
case (.active, .dismissed, false):
    MainAppView()              // Dismissed without key: banner + static carousel
      .withAddKeyBanner()
      .withStaticCarousel()
case (.active, .completed, _):
    MainAppView()              // Normal usage
case (.active, .dismissed, true):
    MainAppView()              // User dismissed but later added key
}
```

First-launch detection: no auth session and backend onboarding status is `not_started`.

---

## Phase 1.5: Apple permission cards

After provider readiness is confirmed and before the AI tour begins, the app presents permission cards inline in the chat view. These cards are the only trigger for Apple system permission prompts.

### Location permission card

- Explains product value: location enables weather, local recommendations, and time-aware responses
- "Enable" button triggers the system location prompt
- "Not now" dismisses without prompting
- If denied, shows a recovery CTA that links to system Settings
- Permission outcome written to backend: `permissions.location`

### Notifications permission card

- Explains product value: task reminders, file completion, assistant attention
- "Enable" / "Not now" behavior mirrors location
- Permission outcome written to backend: `permissions.notifications`

Cards appear sequentially. The AI tour begins after both are resolved (granted, denied, or dismissed). Cards use the same monochrome style as Phase 2 `FeatureIntroCard` components.

**Rule**: Never request system permissions at launch or sign-in. All Apple permission prompts are triggered by explicit user action in Phase 1.5 permission cards.

---

## Phase 2: AI-guided feature discovery

After the Phase 1 modal dismisses and permissions are handled, the user is in the main app with Chat focused. The AI assistant drives feature discovery from chat.

### How it works

- The backend detects incomplete onboarding and injects onboarding context into the system prompt
- The AI greets the user by name (if provided in Step 4) and begins the feature tour
- For each feature, a `FeatureIntroCard` appears inline in the chat view
- The AI waits for user acknowledgment before advancing
- Users can say "skip", "next", or "show me everything" to control pacing
- A persistent "Skip Tour" option is always available

### Tour sequence

| Feature | Card content |
|---|---|
| Chat | Home base for asking questions, taking actions across content, web search, and skills |
| Notes + Scratchpad | Capture and organise; Scratchpad always one tap away |
| Tasks | Projects, due dates, recurring tasks; AI creates tasks from conversation |
| Websites | Save articles and links; AI can summarize and answer questions about saved content |
| Files | Upload PDFs, documents, images; AI can search and reference after processing |
| Skills Store | Extend capabilities; three tiers (Required, Standard, Store) |
| Memory | AI learns the user over time; user always in control |
| Widgets + Extensions (optional) | Home screen widgets and Share Extension / Safari Extension |

The closing message marks onboarding complete via the backend API. `first_outcome_completed` is set when the user completes one real action during or after the tour.

### FeatureIntroCard design

- Monochrome card with SF Symbol icon, title, one-line description
- Dismiss button (X) in the top-right corner
- Optional "Try it" CTA button
- Appears inline between chat messages or as a chat overlay
- Slide-in / fade-out using `DesignTokens.Animation.standard` (0.25s)
- SF Symbols use `.primary` / `.secondary` label colors (auto light/dark)

---

## Fallback behavior

### AI unavailable

If the AI fails during Phase 2 (bad key, rate limit, network failure):

- Show a `StaticFeatureCarousel`: a horizontally-scrollable set of `FeatureIntroCard` views covering the same 8 features
- Shown once, dismissable
- User can retry AI setup from Settings

### No API key

If the user skips provider setup entirely:

- Land in the main app with a persistent banner ("Add an API key to start using the assistant")
- Banner links to Settings for provider key entry
- Notes, tasks, websites, and files remain fully functional
- Chat shows an explanation that a key is needed for AI features
- Status: `dismissed` with `provider_connected` milestone false
- When a key is later added from Settings, `provider_connected` is set and the AI tour triggers on the next chat open

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

## Development and testing

### Launch argument: `-resetOnboarding`

Forces onboarding to appear regardless of server-side state. Enables mock auth mode: sign-up and OTP verification auto-succeed, any string is accepted as a valid API key.

Additional flags:
- `-mockAuth`: skip real Supabase calls
- `-skipVerification`: skip the OTP step
- `-prefillProfile`: pre-fill name and location with test data

### Analytics events

| Event | Emitter |
|---|---|
| `onboarding_started` | UI |
| `onboarding_resumed` | UI |
| `onboarding_completed` | Backend |
| `onboarding_dismissed` | UI |
| `provider_key_prompted` | UI |
| `provider_key_connected` | Backend |
| `intent_selected` | Backend |
| `milestone_completed` | Backend |
| `first_outcome_completed` | Backend |
| `permission_prompted` | UI |
| `permission_granted` | UI |
| `permission_denied` | UI |
| `permission_recovery_tapped` | UI |

Each event in the table above has a single designated emitter (UI or backend) to prevent double-counting.

---

## Rules summary

1. **Backend is the source of truth.** All onboarding state is persisted on the backend. iOS renders it; it does not maintain a parallel state machine.
2. **Onboarding is assistant-first.** Provider setup must be offered before the AI tour begins. Chat generation is not available until a key is connected.
3. **Permission prompts require explicit user action.** No location or notification prompts at launch, sign-in, or any time outside Phase 1.5 permission cards.
4. **Skipping is always available.** Provider selection and API key entry each have a "Skip for now" exit. Users who skip still get full access to non-AI features.
5. **Provider-dismissed users get a recovery path.** An add-key banner and static feature carousel must be shown until the user adds a key. Chat must explain why AI features are unavailable.
6. **The AI tour has a static fallback.** If the AI is unavailable during Phase 2, a `StaticFeatureCarousel` covers the same content.
7. **Presentation wrapper only.** Content is identical across iPhone, iPad, and Mac. Only the presentation container (`.fullScreenCover` vs `.sheet`) differs.
8. **Analytics events have a single emitter.** UI and backend must not both emit the same milestone event.

---

## Related docs

- [Authentication](./authentication)
- [iOS Conventions](../platform-strategy/ios-conventions)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [Implementation Gaps](../implementation-gaps)
