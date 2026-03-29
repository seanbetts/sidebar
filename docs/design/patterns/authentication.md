---
title: Authentication
description: How sideBar manages auth state, sessions, biometric lock, offline access, and sign-out across all platforms.
---

| Field | Value |
|---|---|
| Status | approved |
| Owner | both |
| Outputs | this doc |
| Dependencies | [ios-conventions](../platform-strategy/ios-conventions), [wait-ux](./wait-ux) |

## Purpose

Define how sideBar should handle authentication state, session lifecycle, and the transitions a user moves through — from first sign-in through to biometric lock, offline access, token expiry, and sign-out. This doc covers both the user-visible patterns and the underlying state model that drives them.

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
3. If the session exists but the offline window has expired: attempt a token refresh. Success → `.active`; auth error → `signedOut` with full state clear; network error → `.stale`
4. If no session: `signedOut` → show login

The app must not show a blank main UI while auth state is being determined. Show a loading state or the login screen until the initial state is resolved.

### Token refresh

Tokens are refreshed proactively — 10 minutes before expiry — rather than reactively on failure. This prevents API calls from failing mid-session.

- **Foreground**: Refresh triggered on app activation when token is within 10 minutes of expiry
- **Background**: `BGAppRefreshTask` scheduled every 15 minutes when app backgrounds; keeps tokens fresh for users who leave the app open
- **On refresh failure**: Transient errors (network) → `.stale`; hard auth errors (expired refresh token, invalid JWT) → `signedOut` with full state clear

A 60-second cooldown prevents refresh thrashing if multiple failures occur in rapid succession.

### Stale state recovery

When in `.stale`, the app:
- Continues to function with locally cached data
- Surfaces a non-blocking banner or toast indicating sync is paused
- Provides a manual "Retry" action so the user is not left waiting for the next background refresh
- Automatically transitions to `.active` on next successful token refresh

**Rule**: Do not block the UI in `.stale` state. The user can continue working. Surface the degraded state clearly but without demanding action.

---

## Sign-in

Email and password authentication via Supabase. The sign-in screen is the only entry point for `signedOut` users — there is no partial access or guest mode.

### Rate limiting

Failed sign-in attempts are rate-limited: 5 failures triggers a 5-minute lockout. The lockout timer and attempt count must be persisted to storage — an in-memory-only lockout resets on app restart and provides no meaningful protection.

The lockout state is shown in the login UI with a countdown.

### Last email prefill

The last successfully signed-in email is remembered and prefilled on the login form. This is cleared on sign-out.

---

## Sign-up and OTP verification

New users sign up with email and password (minimum 8 characters). An OTP verification email is sent before the session is activated. The app holds a `pendingVerificationEmail` state and shows the OTP entry screen until verification completes or the user cancels.

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

### macOS

macOS supports Touch ID. The same biometric lock pattern applies — lock screen shown after grace period, auto-triggers on app activation, passcode fallback available.

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
3. All in-memory and cached data cleared (stores, view models, caches, drafts, widget data, spotlight indexes)
4. Navigation reset to root

The sign-out wipe is intentionally thorough — no data from the previous session should be visible after sign-out, including to a different user who signs into the same device.

**Rule**: Sign-out must always clear all user data. There is no "stay signed in on this device" partial sign-out.

---

## Deep link handling

Deep links that arrive while the app is not in `.active` state must be deferred, not silently dropped:

- If the app is loading (auth state not yet determined): queue the deep link and process after auth resolves
- If `signedOut`: complete sign-in, then process the queued deep link
- If biometric lock is showing: complete biometric auth, then process the deep link

**Rule**: Deep links must never route to feature content before auth is complete. Silent failure (routing to a blank/loading screen) is not acceptable.

---

## Auth error surfaces

Auth errors are surfaced non-modally in order of severity:

| Error type | Surface |
|---|---|
| Token refresh failed (transient) | Toast: "Sync paused — retrying..." |
| Token refresh failed (hard auth error) | Sign-out with full data clear; return to login |
| Sign-in failed (wrong credentials) | Inline error below email/password fields |
| Sign-in rate limited | Inline lockout message with countdown |
| Biometric failure | Inline error on lock screen |
| Session expired mid-session | Toast, then transition to `.stale` |

Auth errors must be cleared automatically when auth state transitions successfully. A stale error toast should not persist after the session is recovered.

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

1. **Three states only: `signedOut`, `stale`, `active`.** No additional states should be introduced.
2. **`.stale` is functional, not an error.** The user continues working with cached data. Sync resumes automatically.
3. **Always provide a manual retry for `.stale` state.** Do not rely solely on background/foreground transitions to recover.
4. **Rate limiting must be persisted.** In-memory lockout provides no meaningful protection against brute force.
5. **Offline window must be backed by Keychain.** Do not rely on UserDefaults for security-relevant timestamps.
6. **Deep links are deferred, never silently dropped.** Auth must complete before feature content is shown.
7. **Biometric lock always has an exit path.** Passcode fallback and sign-out must always be available.
8. **Sign-out is complete.** All user data is cleared. No partial sign-out.
9. **Auth errors clear automatically on recovery.** Do not leave stale error toasts after the session is restored.

---

## Related docs

- [iOS Conventions](../platform-strategy/ios-conventions)
- [Wait UX](./wait-ux)
- [Feedback and Haptics](./feedback-and-haptics)
- [Implementation Gaps](../implementation-gaps)
