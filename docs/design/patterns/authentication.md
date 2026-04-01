---
title: Authentication
description: How sideBar manages auth state, sessions, biometric lock, offline access, and sign-out across all platforms.
---

## Purpose

Define how sideBar handles authentication state, session lifecycle, and the transitions a user moves through — from sign-up through to biometric lock, offline access, token expiry, and sign-out. This doc covers both the user-visible patterns and the underlying state model that drives them.

This doc is the design system view: how auth should feel and behave.

---

## Account model

sideBar uses app-owned, password-primary accounts. Email and password is the canonical login path. Supabase provides auth infrastructure but is an adapter, not the product model — client code calls product-shaped interfaces, not Supabase-specific APIs.

Each account has one primary credential path: `email_password`. Passkeys and Sign in with Apple are not part of the current model. If either is added later:

- Passkeys are an explicit security upgrade, not a silent alternate identity
- Sign in with Apple creates a distinct account family, not a merge with password accounts
- Neither should silently turn a password account into a mixed-identity account

---

## Auth state model

The app uses a three-state model:

| State | Meaning | User experience |
|---|---|---|
| `signedOut` | No usable session. User must authenticate. | Login screen shown |
| `active` | Session valid and network-authenticated. | Full app access, sync running |
| `stale` | Session exists but cannot be verified (network unavailable or refresh failed). | App usable with cached data, sync paused |

**Rule**: Treat `.stale` as a degraded-but-functional state, not an error state. The user should be able to continue working. Sync resumes automatically when the session is recovered.

The transition from `.stale` back to `.active` happens automatically on the next successful token refresh — no user action required if the network returns. If the user wants to force it, a manual retry should be available.

---

## Session lifecycle

### App launch

On launch, the app determines initial auth state before showing any content:

1. Check Keychain for a stored session
2. If a valid session exists within the 24-hour offline access window: restore as `.active` (if network is available) or `.stale` (if offline)
3. If the session exists but the offline window has expired: attempt a token refresh. Success → `.active`; auth error → `signedOut`; network error → `.stale`
4. If no session: `signedOut`

**Rule**: `signedOut` always shows the login screen — no exceptions, no partial access. Any transition to `signedOut`, whether from sign-out, token expiry, or failed session restore, must result in the login screen being shown and all user data cleared.

While auth state is being determined on launch, show a neutral loading state — not the login screen. The login screen only appears once auth state has resolved to `signedOut`. Showing login prematurely would interrupt users who are simply returning to an active or stale session.

### Token refresh

Tokens are refreshed proactively — 10 minutes before expiry — rather than reactively on failure. This prevents API calls from failing mid-session.

- **Foreground**: Refresh triggered on app activation when token is within 10 minutes of expiry
- **Background**: `BGAppRefreshTask` scheduled every 15 minutes when app backgrounds; keeps tokens fresh for users who leave the app open
- **On refresh failure**: Transient errors (network) → `.stale`; hard auth errors (expired refresh token, invalid JWT) → `signedOut` with full state clear

A 60-second cooldown prevents refresh thrashing if multiple failures occur in rapid succession.

### Stale state recovery

When in `.stale`, the app:
- Continues to function with locally cached data
- Surfaces a non-blocking retry pill if stale state persists for 10 continuous seconds
- Provides a manual "Retry" action in that pill so the user is not left waiting for the next background refresh
- Automatically transitions to `.active` on next successful token refresh

Short-lived stale periods should not show visible chrome. If the session recovers before the 10-second threshold, show nothing.

**Rule**: Do not block the UI in `.stale` state. The user can continue working. Surface the degraded state clearly but without demanding action.

---

## Sign-in

Email and password is the only primary credential path. The sign-in screen is the only entry point for `signedOut` users — there is no partial access or guest mode.

Two entry modes converge on the same flow: explicit email/password entry, and AutoFill-assisted credential selection through AuthenticationServices (`ASAuthorizationPasswordProvider`).

### AutoFill and content types

Login fields must use the correct content types for AutoFill:

- Email field: username content type
- Password field: password content type

Do not use embedded browsers or web views for first-party login. All sign-in UI is native.

### Rate limiting

Failed sign-in attempts are rate-limited: 5 failures triggers a 5-minute lockout. The lockout timer and attempt count must be persisted to storage — an in-memory-only lockout resets on app restart and provides no meaningful protection.

The lockout state is shown in the login UI with a countdown.

### Last email prefill

The last successfully signed-in email is remembered and prefilled on the login form. This is cleared on sign-out.

---

## Sign-up and OTP verification

New users sign up with email and password (minimum 8 characters). An OTP verification email is sent before the session is activated. The app holds a `pendingVerificationEmail` state and shows the OTP entry screen until verification completes or the user cancels.

The OTP input field must use the one-time-code content type so verification benefits from AutoFill. Do not force the user through a browser for sign-up or verification.

---

## Password reset

1. User taps "Forgot password" and enters their email
2. Backend starts the reset flow and sends a reset link
3. Tapping the link opens sideBar directly and restores a recovery session in-app
4. The app presents a native "Enter a new password" screen and completes the password update without a web detour
5. User returns to sign-in with a clear success state

The current implementation is link-based. A native reset-code entry path is not
part of the shipped flow yet.

Email is the only recovery channel for password accounts. Recovery must not branch into unrelated identity systems — Sign in with Apple is not a fallback for password-rooted accounts.

---

## Session management in settings

Settings should support:

- Change password (requires biometric reauth)
- Sign out
- Biometric unlock configuration

---

## Biometric lock

Biometric lock is a separate layer on top of auth state — it does not change the session, only controls access to the app UI.

### Behaviour

- Biometric lock is opt-in (`biometricUnlockEnabled` preference)
- When enabled, the app shows a lock screen on re-entry after a 5-minute grace period in the background
- The lock screen auto-triggers authentication on appear (one automatic attempt per foreground transition)
- If automatic auth fails, the user can retry manually or fall back to device passcode
- Sign-out is available directly from the lock screen

### Grace period

If the user backgrounds the app and returns within 5 minutes, the lock screen is not shown. This prevents friction for brief interruptions (switching to check a message, etc.).

### Failure states

| Failure | Response |
|---|---|
| Biometry locked out | Show error + "Use Passcode" button |
| User cancelled | Stay on lock screen, allow retry |
| Biometry not available/enrolled | Show setup instructions |
| No passcode set | Guide to device settings |

**Rule**: Always provide a fallback path. Never leave the user stuck on the lock screen with no way to proceed — passcode fallback or sign-out must always be available.

### Biometric reauth for sensitive actions

Separate from the lock screen, biometric reauth is required for specific in-session actions:

- Changing password

This is a local trust gate, not a session operation — it does not affect the backend session. If biometrics fail, offer passcode fallback. Do not skip the reauth step.

### macOS

macOS supports Touch ID. The same biometric lock pattern applies — lock screen shown after grace period, auto-triggers on app activation, passcode fallback available. The same reauth requirements apply for sensitive settings actions.

---

## Offline access

When the user has a stored session and the device is offline (or connectivity is unavailable), the app allows access for up to 24 hours without a fresh token.

### Offline unlock

If the user opens the app offline with a valid cached session:
- Biometric authentication is required first (if biometric lock is enabled)
- Session is restored in `.stale` state — not `.active`
- The user can work with cached data; sync resumes when connectivity returns

### Offline window expiry

After 24 hours without a successful token refresh, the offline window expires. On next launch, the app attempts a token refresh. If that fails due to a hard auth error (not just network unavailability), the session is cleared and the user must sign in again.

The 24-hour window should be backed by a value stored in Keychain alongside the token, not in UserDefaults. This prevents the offline window from being trivially reset by clearing UserDefaults while Keychain remains intact.

---

## Sign-out

Sign-out is explicit and complete:

1. Best-effort server-side sign-out (Supabase session revoked)
2. All persisted auth state cleared from Keychain
3. Extension auth state cleared (share extension, Safari extension) via shared Keychain group
4. All in-memory and cached data cleared (stores, view models, caches, drafts, widget data, spotlight indexes)
5. Navigation reset to root

The sign-out wipe is intentionally thorough — no data from the previous session should be visible after sign-out, including to a different user who signs into the same device.

**Rule**: Sign-out must always clear all user data. There is no "stay signed in on this device" partial sign-out.

---

## Deferred actions

Some user-initiated operations arrive while auth state is not fully resolved. These must be deferred until auth completes, not silently dropped.

### Deep links

Deep links that arrive while the app is not in `.active` state:

- If the app is loading (auth state not yet determined): queue the deep link and process after auth resolves
- If `signedOut`: complete sign-in, then process the queued deep link
- If biometric lock is showing: complete biometric auth, then process the deep link
- If `.stale`: process immediately. The destination works from cached data, same as any other navigation in stale state.

**Rule**: Deep links must never route to feature content before auth is complete. Silent failure (routing to a blank/loading screen) is not acceptable. However, `.stale` counts as authenticated, so deep links should not be blocked by offline state.

### Website saves (share extension and Safari extension)

A save triggered from the share sheet or Safari extension may arrive when the app is `signedOut`, locked, or loading. The save must be queued and completed once auth resolves — it must not be silently discarded.

- If `signedOut`: queue the save, complete sign-in, then process it
- If biometric lock is showing: queue the save, complete biometric auth, then process it
- If `.stale`: process immediately using the cached session; sync when connectivity returns

Unlike deep links, website saves do not require navigation after completion. The user should receive a confirmation (toast or notification) once the save completes, but is not routed into the app unless they tap the confirmation.

---

## Auth error surfaces

Auth errors must be product-facing and action-oriented, not provider-facing. "Check your password." not "Supabase auth error: invalid_grant". Framework-level cancellations (dismissing a system sheet, cancelling a biometric prompt) are neutral outcomes, not failures — they should return the user to the prior screen without escalating.

Auth errors are surfaced non-modally in order of severity:

| Error type | Surface |
|---|---|
| Token refresh failed (transient) | No immediate surface; if `.stale` persists for 10 seconds, show retry pill: "Sync paused" |
| Token refresh failed (hard auth error) | Sign-out with full data clear; return to login |
| Sign-in failed (wrong credentials) | Inline error below email/password fields |
| Sign-in rate limited | Inline lockout message with countdown |
| Biometric failure | Inline error on lock screen |
| Session expired mid-session | Transition to `.stale`; if it persists for 10 seconds, show retry pill |

Auth errors must be cleared automatically when auth state transitions successfully. A stale retry pill should not persist after the session is recovered.

---

## Web

The web app uses the same Supabase session but with a browser-appropriate auth model:

- Session stored in browser localStorage (managed by Supabase SDK)
- Token refreshed automatically by the Supabase client on API calls
- Session persisted and restored across page loads and browser restarts
- `onAuthStateChange` triggers a full SvelteKit `invalidateAll()` on sign-in/sign-out, ensuring all server-loaded data is refreshed

The web app has no biometric lock (no API equivalent in browsers), no offline access mode (browsers do not have Keychain-equivalent secure storage for tokens), and no background token refresh (page must be open). These are accepted asymmetries.

**Sign-out on web** clears the Supabase session and redirects to the login page. It does not need to clear IndexedDB or other storage since web does not maintain a persistent write queue or cache equivalent to native.

---

## Rules summary

1. **Three states only: `signedOut`, `stale`, `active`.** No additional top-level states should be introduced.
2. **`.stale` is functional, not an error.** The user continues working with cached data. Sync resumes automatically.
3. **Always provide a manual retry for `.stale` state.** Do not rely solely on background/foreground transitions to recover.
4. **Rate limiting must be persisted.** In-memory lockout provides no meaningful protection against brute force.
5. **Offline window must be backed by Keychain.** Do not rely on UserDefaults for security-relevant timestamps.
6. **Deferred actions are queued, never silently dropped.** Deep links and website saves must be held until auth completes, then processed.
7. **Biometric lock always has an exit path.** Passcode fallback and sign-out must always be available.
8. **Sign-out is complete.** All user data is cleared. No partial sign-out.
9. **Auth errors clear automatically on recovery.** Do not leave stale error toasts after the session is restored.
10. **No embedded browsers for first-party auth.** All sign-in, sign-up, verification, and reset flows are native.
11. **Auth fields use correct content types.** Email uses username, password uses password, OTP uses one-time-code — for AutoFill.
12. **Auth errors are product-facing.** Never expose provider error codes. Framework cancellations are neutral, not failures.
13. **One primary credential path per account.** Email/password only. Do not silently merge with Sign in with Apple or passkey identities.

---

## Related docs

- [iOS Conventions](../platform-strategy/ios-conventions)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [Implementation Gaps](../implementation-gaps)
