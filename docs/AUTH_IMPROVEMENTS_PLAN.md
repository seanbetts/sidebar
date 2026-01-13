# Authentication & Login Improvements - Implementation Plan

**Project:** sideBar iOS/macOS App
**Date:** 2026-01-13
**Status:** Planning Phase

---

## Executive Summary

The sideBar app has a well-architected authentication system with Supabase integration, biometric unlock support, and secure keychain storage. However, critical security issues, UX gaps, and missing features require immediate attention before production deployment.

**Current State:**
- ✅ Clean SwiftUI login interface
- ✅ Biometric authentication (Face ID/Touch ID)
- ✅ Keychain-based credential storage
- ✅ Proper separation of concerns
- ✅ Supabase authentication integration

**Critical Issues Identified:**
- ❌ Missing Face ID privacy description (App Store rejection + crash risk)
- ❌ Weak keychain security settings
- ❌ Incorrect biometric policy (falls back to passcode silently)
- ❌ No session refresh mechanism
- ❌ Silent keychain failures

**Estimated Implementation Time:** 3-5 days for all phases

---

## Table of Contents

1. [Critical Issues (Must Fix)](#critical-issues-must-fix)
2. [Security Improvements](#security-improvements)
3. [Login Screen UI Improvements](#login-screen-ui-improvements)
4. [Biometric Authentication Improvements](#biometric-authentication-improvements)
5. [Session Management Improvements](#session-management-improvements)
6. [Accessibility Improvements](#accessibility-improvements)
7. [Implementation Plan](#implementation-plan)
8. [Testing Strategy](#testing-strategy)
9. [File Reference Guide](#file-reference-guide)

---

## Critical Issues (Must Fix)

### 1. Missing Face ID Privacy Description 🚨 CRASH RISK

**Severity:** CRITICAL
**Impact:** App Store rejection, runtime crash on iOS devices with Face ID
**Effort:** 5 minutes
**Applicability:** ✅ Applies (required for current Face ID usage)

**Issue:**
- App uses Face ID but lacks required `NSFaceIDUsageDescription` in Info.plist
- iOS will crash when `LAContext.evaluatePolicy()` is called without this key
- Apple App Store review will reject the app

**Files:**
- `ios/sideBar/sideBar/Info.plist`

**Fix:**
```xml
<key>NSFaceIDUsageDescription</key>
<string>We use Face ID to securely unlock sideBar and protect your data.</string>
```

**Testing:**
- Run on physical iOS device with Face ID
- Attempt biometric unlock
- Verify no crash and proper Face ID prompt appears

---

### 2. Weak Keychain Security Settings 🔒 HIGH SECURITY RISK

**Severity:** HIGH
**Impact:** Authentication tokens accessible when device locked, vulnerable to forensic extraction
**Effort:** 5 minutes
**Applicability:** ✅ Applies (auth tokens should be `WhenUnlockedThisDeviceOnly`)

**Issue:**
- Currently uses `kSecAttrAccessibleAfterFirstUnlock`
- This means keychain items are accessible any time after device boots, even when locked
- Malware or forensic tools can extract tokens without unlocking device
- Not appropriate for authentication credentials

**File:**
- `ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift:52`

**Current Code:**
```swift
#if os(iOS)
attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
#endif
```

**Fix:**
```swift
#if os(iOS)
attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
#endif
```

**Why This Is Better:**
- `WhenUnlocked` - Only accessible when device is actively unlocked
- `ThisDeviceOnly` - Cannot be backed up to iCloud or restored to another device
- Provides maximum security for authentication tokens

**Testing:**
- Lock device and verify app requires unlock to access keychain
- Verify tokens don't sync to other devices via iCloud

---

### 3. Incorrect Biometric Policy 🔑 UX ISSUE

**Severity:** HIGH
**Impact:** Users enable Face ID but get passcode prompt instead
**Effort:** 5 minutes
**Applicability:** ✅ Applies, with adjustment (choose explicit fallback behavior)

**Issue:**
- Uses `.deviceOwnerAuthentication` policy
- This policy silently falls back to device passcode if biometric fails or is unavailable
- Users who explicitly enabled "Face ID unlock" expect to see Face ID, not passcode
- Confusing and inconsistent UX

**File:**
- `ios/sideBar/sideBar/Views/Auth/BiometricLockView.swift:62`

**Current Code:**
```swift
context.evaluatePolicy(
    .deviceOwnerAuthentication,
    localizedReason: "Unlock sideBar to continue."
)
```

**Fix:**
```swift
context.evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,
    localizedReason: "Unlock sideBar to continue."
)
```

**Fallback Handling:**
```swift
private func authenticate() {
    guard !isAuthenticating else { return }
    isAuthenticating = true
    defer { isAuthenticating = false }

    let context = LAContext()

    // Check if biometrics are actually available
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        // Biometrics not available - offer passcode fallback or sign out
        handleBiometricUnavailable(error: error)
        return
    }

    context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Unlock sideBar to continue."
    ) { success, error in
        DispatchQueue.main.async {
            if success {
                onUnlock()
            } else if let error = error {
                handleAuthenticationError(error)
            }
        }
    }
}
```

**Testing:**
- Enable biometric unlock in settings
- Lock app and verify Face ID/Touch ID prompt appears (not passcode)
- Test on device with biometric disabled to verify graceful fallback

---

### 4. Silent Keychain Failures 💥 RELIABILITY ISSUE

**Severity:** HIGH
**Impact:** Authentication state lost without error reporting, users mysteriously logged out
**Effort:** 30 minutes
**Applicability:** ✅ Applies (add logging/toast on failure)

**Issue:**
- Keychain operations that fail return `nil` without throwing
- Failures are invisible to calling code
- Users could lose sessions without understanding why
- No logging or telemetry for keychain issues

**File:**
- `ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift`

**Current Pattern:**
```swift
public func load(key: String) -> String? {
    // ... keychain query ...
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecSuccess, let data = result as? Data {
        return String(data: data, encoding: .utf8)
    }
    return nil  // ← Silent failure
}
```

**Fix:**
```swift
public enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
    case unknown

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Authentication data not found. Please sign in again."
        case .duplicateItem:
            return "Duplicate keychain entry detected."
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Stored authentication data is corrupted."
        case .unknown:
            return "An unknown keychain error occurred."
        }
    }
}

public func load(key: String) throws -> String? {
    // ... keychain query ...
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    case errSecItemNotFound:
        return nil  // Not an error - item just doesn't exist
    case errSecDuplicateItem:
        throw KeychainError.duplicateItem
    default:
        throw KeychainError.unexpectedStatus(status)
    }
}
```

**Testing:**
- Unit tests for all error cases
- Integration test simulating keychain corruption
- Test recovery flow when load throws

---

### 5. iCloud Keychain Sync Enabled ☁️ SECURITY ISSUE

**Severity:** MEDIUM-HIGH
**Impact:** Authentication tokens sync to iCloud, accessible from other devices
**Effort:** 2 minutes

**Issue:**
- Keychain items default to `kSecAttrSynchronizable = true` unless explicitly disabled
- Auth tokens are backed up to iCloud and sync to other devices
- Violates principle of device-bound authentication
- Could expose tokens to compromised iCloud account

**File:**
- `ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift:52`

**Fix:**
```swift
attributes[kSecAttrSynchronizable as String] = false
```

**Testing:**
- Sign in on device A
- Check keychain on device B (same iCloud account)
- Verify tokens don't appear on device B

---

### 6. No Session Refresh Mechanism ⏰ SESSION MANAGEMENT

**Severity:** MEDIUM-HIGH
**Impact:** Users get hard-logged out when access token expires
**Effort:** 2-3 hours

**Issue:**
- Access tokens have expiration but are never refreshed
- When token expires, `session.isExpired` check immediately clears auth state
- No warning, no refresh attempt - just sudden logout
- Poor UX for users with app open for extended periods

**File:**
- `ios/sideBar/sideBar/Services/Auth/SupabaseAuthAdapter.swift`

**Current Code:**
```swift
private func applySession(_ session: Session?) {
    guard let session, !session.isExpired else {
        restoreSession(accessToken: nil, userId: nil)  // ← Hard logout
        return
    }
    restoreSession(accessToken: session.accessToken, userId: session.user.id.uuidString)
}
```

**Fix Strategy:**
1. Monitor token expiration time
2. Proactively refresh 5 minutes before expiry
3. Use Supabase's built-in refresh token mechanism
4. Show warning if refresh fails
5. Only logout if refresh explicitly fails

**Implementation:**
```swift
private var refreshTimer: Task<Void, Never>?

private func scheduleTokenRefresh(expiresAt: Date) {
    refreshTimer?.cancel()

    let refreshTime = expiresAt.addingTimeInterval(-300) // 5 min before expiry
    let delay = refreshTime.timeIntervalSinceNow

    guard delay > 0 else {
        // Already expired or expiring soon - refresh immediately
        Task { await refreshSession() }
        return
    }

    refreshTimer = Task {
        try? await Task.sleep(for: .seconds(delay))
        await refreshSession()
    }
}

private func refreshSession() async {
    do {
        let session = try await supabase.auth.session
        applySession(session)
    } catch {
        // Refresh failed - notify user before logging out
        await showSessionExpiryWarning()
    }
}
```

**Testing:**
- Mock token expiration
- Verify refresh happens automatically
- Test refresh failure handling
- Test app backgrounding during refresh

---

## Security Improvements

### 7. Add Encryption Layer Over Keychain

**Priority:** Medium
**Effort:** 4-6 hours

**Rationale:**
- Defense in depth - keychain is secure but adding encryption provides additional protection
- Protects against keychain extraction vulnerabilities
- Could use device-bound key (Secure Enclave) for encryption

**Implementation:**
```swift
// Use CryptoKit to encrypt data before storing in keychain
import CryptoKit

private func encryptData(_ data: Data) throws -> Data {
    let key = SymmetricKey(size: .bits256)
    let sealedBox = try AES.GCM.seal(data, using: key)
    return sealedBox.combined!
}
```

**Considerations:**
- Key management complexity
- Performance impact
- Recovery if key is lost

---

### 8. Add Biometric-Bound Keychain Access

**Priority:** Medium
**Effort:** 2 hours

**Current:** Keychain accessible when device unlocked
**Improvement:** Require biometric authentication to access keychain

**Implementation:**
```swift
let accessControl = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    .biometryCurrentSet,
    nil
)
attributes[kSecAttrAccessControl as String] = accessControl
```

**Benefits:**
- Tokens require Face ID/Touch ID to access
- Even with device unlocked, biometric needed to read keychain
- Maximum security for sensitive credentials

**Tradeoff:**
- User must authenticate even after relaunch
- May be too aggressive for some use cases

---

### 9. Implement Rate Limiting Detection

**Priority:** Low-Medium
**Effort:** 1 hour

**Issue:**
- Backend may throttle login attempts
- Users see generic error with no guidance
- No indication of temporary vs permanent failure

**Implementation:**
```swift
private func handleSignInError(_ error: Error) {
    if let apiError = error as? APIError {
        switch apiError.statusCode {
        case 429:
            errorMessage = "Too many login attempts. Please wait a few minutes and try again."
        case 401:
            errorMessage = "Email or password is incorrect."
        case 503:
            errorMessage = "Service temporarily unavailable. Please try again later."
        default:
            errorMessage = "Unable to sign in. Please check your connection and try again."
        }
    } else {
        errorMessage = "Unable to sign in. Please check your connection and try again."
    }
}
```

---

### 10. Add Security Event Logging

**Priority:** Low
**Effort:** 2-3 hours

**Purpose:** Track authentication events for security monitoring

**Events to Log:**
- Successful login (timestamp, device info)
- Failed login attempts
- Session refresh success/failure
- Biometric unlock success/failure
- Logout (user-initiated vs forced)
- Keychain access errors

**Privacy Considerations:**
- Never log passwords or tokens
- Hash email addresses before logging
- Implement log retention policy
- Consider GDPR implications

---

## Login Screen UI Improvements

### 11. Add Password Visibility Toggle ⭐ HIGH PRIORITY

**Priority:** HIGH
**Impact:** Major UX improvement for mobile keyboards
**Effort:** 1-2 hours

**Issue:** Users can't verify typed password, leading to typos

**Implementation:**

1. **Create SecureFieldWithToggle Component**
```swift
public struct SecureFieldWithToggle: View {
    let title: String
    @Binding var text: String
    var textContentType: UITextContentType?

    @State private var isSecure: Bool = true

    public var body: some View {
        HStack {
            if isSecure {
                SecureField(title, text: $text)
                    .textContentType(textContentType)
            } else {
                TextField(title, text: $text)
                    .textContentType(textContentType)
            }

            Button {
                isSecure.toggle()
            } label: {
                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? "Show password" : "Hide password")
        }
    }
}
```

2. **Replace SecureField in LoginView**
```swift
SecureFieldWithToggle(
    title: "Password",
    text: $password,
    textContentType: .password
)
.textFieldStyle(.roundedBorder)
.focused($focusedField, equals: .password)
.submitLabel(.go)
```

**Testing:**
- Toggle between secure/visible states
- Verify accessibility labels
- Test with password managers
- Verify on both iOS and macOS

---

### 12. Add Keyboard Dismiss Gesture ⭐ HIGH PRIORITY

**Priority:** HIGH
**Impact:** Basic iOS UX expectation
**Effort:** 5 minutes

**Issue:** Keyboard stays up, can't dismiss by tapping outside

**Implementation:**
```swift
// In LoginView.swift body
.onTapGesture {
    focusedField = nil
}
.scrollDismissesKeyboard(.interactively)  // iOS 16+
```

**Alternative for Older iOS:**
```swift
.gesture(
    TapGesture().onEnded {
        focusedField = nil
    }
)
```

---

### 13. Add Clear Buttons on Text Fields

**Priority:** Medium
**Effort:** 30 minutes

**Implementation:**
```swift
HStack {
    TextField("Email", text: $email)
        .textContentType(.emailAddress)

    if !email.isEmpty {
        Button {
            email = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}
```

---

### 14. Add Real-Time Email Validation

**Priority:** Medium
**Effort:** 30 minutes

**Implementation:**
```swift
private var isValidEmail: Bool {
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
    return emailPredicate.evaluate(with: email.trimmingCharacters(in: .whitespaces))
}

// In email field
HStack {
    TextField("Email", text: $email)

    if !email.isEmpty {
        Image(systemName: isValidEmail ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isValidEmail ? .green : .orange)
            .font(.callout)
    }
}
```

---

### 15. Improve Error Styling

**Priority:** Medium
**Effort:** 30 minutes

**Current:** Plain red text
**Improved:** Styled alert with icon and background

**Implementation:**
```swift
if let errorMessage {
    HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 4) {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.callout)
            Text("Double-check your credentials and connection, then try again.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    .padding(12)
    .background(Color.red.opacity(0.1))
    .cornerRadius(8)
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

---

### 16. Add Loading State Text

**Priority:** Low
**Effort:** 1 minute

**Implementation:**
```swift
Text(isSigningIn ? "Signing in..." : "Sign In")
```

---

### 17. Add Success Animation

**Priority:** Low
**Effort:** 1 hour

**Implementation:**
```swift
@State private var showSuccess: Bool = false

// After successful sign-in
withAnimation(.spring(response: 0.3)) {
    showSuccess = true
}

// Add to view
if showSuccess {
    ZStack {
        Color.green.opacity(0.9)
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.white)
    }
    .transition(.scale.combined(with: .opacity))
    .zIndex(100)
}
```

---

### 18. Fix Password Trimming Inconsistency

**Priority:** Low
**Effort:** 1 minute

**Decision Required:** Should passwords be trimmed?

**Recommendation:** Do NOT trim passwords
- Passwords may intentionally contain leading/trailing spaces
- Trimming could prevent valid login
- Email trimming is fine (emails never have meaningful whitespace)

**Implementation:**
```swift
// Keep current email trimming
let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

// Do NOT trim password
try await environment.container.authSession.signIn(email: trimmedEmail, password: password)
```

---

### 19. Add Field Icons

**Priority:** Low (polish)
**Effort:** 15 minutes

**Implementation:**
```swift
HStack {
    Image(systemName: "envelope")
        .foregroundStyle(.secondary)
        .frame(width: 20)
    TextField("Email", text: $email)
}

HStack {
    Image(systemName: "lock")
        .foregroundStyle(.secondary)
        .frame(width: 20)
    SecureField("Password", text: $password)
}
```

---

## Biometric Authentication Improvements

### 20. Fix Biometric Lock Timing ⭐ HIGH PRIORITY

**Priority:** HIGH
**Impact:** Prevents annoying re-authentication on brief interruptions
**Effort:** 5 minutes

**Issue:** App locks on any scene phase change, including notifications

**File:** `ios/sideBar/sideBar/Views/ContentView.swift:57`

**Current Code:**
```swift
.onChange(of: scenePhase) { _, newValue in
    if newValue != .active && biometricUnlockEnabled {
        isBiometricUnlocked = false  // ← Too aggressive
    }
}
```

**Fix:**
```swift
.onChange(of: scenePhase) { _, newValue in
    if newValue == .background && biometricUnlockEnabled {
        isBiometricUnlocked = false  // ← Only lock when backgrounded
    }
}
```

**Testing:**
- Pull down notification center → should NOT lock
- Swipe up to multitasking → should NOT lock
- Activate Siri → should NOT lock
- Switch to another app → SHOULD lock
- Lock device → SHOULD lock

---

### 21. Add Biometric Availability Monitoring

**Priority:** Medium
**Effort:** 2 hours

**Issue:** If user disables Face ID in Settings while app is running, app doesn't react

**Implementation:**
```swift
@MainActor
class BiometricMonitor: ObservableObject {
    @Published var biometryType: LABiometryType = .none
    @Published var isAvailable: Bool = false

    private var timer: Timer?

    func startMonitoring() {
        updateStatus()
        // Check every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateStatus() {
        let context = LAContext()
        var error: NSError?
        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = context.biometryType
    }
}
```

**Usage:**
```swift
// In AppEnvironment
@Published var biometricMonitor = BiometricMonitor()

// Start monitoring when authenticated
if isAuthenticated {
    biometricMonitor.startMonitoring()
}

// React to changes
.onChange(of: biometricMonitor.isAvailable) { _, newValue in
    if !newValue && biometricUnlockEnabled {
        // Biometric became unavailable - notify user
        showBiometricUnavailableAlert = true
    }
}
```

---

### 22. Improve Biometric Error Handling

**Priority:** Medium
**Effort:** 1 hour

**Current:** Generic error messages
**Improved:** Specific guidance for each error type

**Implementation:**
```swift
private func handleAuthenticationError(_ error: Error) {
    guard let laError = error as? LAError else {
        errorMessage = "Authentication failed. Please try again."
        return
    }

    switch laError.code {
    case .biometryLockout:
        errorMessage = "Too many failed attempts. Use your device passcode to unlock."
        showPasscodeFallback = true
    case .biometryNotEnrolled:
        errorMessage = "Face ID is not set up. Please enable it in Settings."
    case .biometryNotAvailable:
        errorMessage = "Face ID is not available on this device."
    case .userCancel:
        errorMessage = nil  // User cancelled intentionally
    case .userFallback:
        errorMessage = "Please use your device passcode."
        showPasscodeFallback = true
    case .passcodeNotSet:
        errorMessage = "Please set a device passcode in Settings to use Face ID."
    case .authenticationFailed:
        errorMessage = "Face ID authentication failed. Please try again."
    default:
        errorMessage = "Unable to authenticate. Please try again."
    }
}
```

---

### 23. Add Passcode Fallback Option

**Priority:** Medium
**Effort:** 2-3 hours

**Current:** Only sign out option when biometric fails
**Improved:** Allow fallback to device passcode

**Implementation:**
```swift
// In BiometricLockView
@State private var showPasscodeFallback: Bool = false

if showPasscodeFallback {
    Button {
        authenticateWithPasscode()
    } label: {
        Text("Use Passcode")
    }
    .buttonStyle(.bordered)
}

private func authenticateWithPasscode() {
    let context = LAContext()
    context.evaluatePolicy(
        .deviceOwnerAuthentication,  // ← Allows passcode fallback
        localizedReason: "Enter your device passcode."
    ) { success, error in
        DispatchQueue.main.async {
            if success {
                onUnlock()
            } else if let error = error {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

---

### 24. Add Biometric Hint After First Login

**Priority:** Low
**Effort:** 30 minutes

**Implementation:**
```swift
// Store whether hint has been shown
@AppStorage("hasShownBiometricHint") private var hasShownBiometricHint: Bool = false

// After successful login, if biometric available and not enabled
if !hasShownBiometricHint && canUseBiometrics && !biometricUnlockEnabled {
    showBiometricHintAlert = true
    hasShownBiometricHint = true
}

.alert("Enable Face ID?", isPresented: $showBiometricHintAlert) {
    Button("Enable in Settings") {
        // Navigate to settings
    }
    Button("Not Now", role: .cancel) { }
} message: {
    Text("Unlock sideBar quickly and securely with Face ID.")
}
```

---

## Session Management Improvements

### 25. Implement Token Refresh (Covered in #6)

See Critical Issues section for full implementation.

---

### 29. Add Session Expiry Warning

**Priority:** Medium
**Effort:** 1 hour

**Implementation:**
```swift
// Show alert 5 minutes before token expires
.alert("Session Expiring Soon", isPresented: $showSessionExpiryWarning) {
    Button("Stay Signed In") {
        Task { await refreshSession() }
    }
    Button("Sign Out") {
        signOut()
    }
} message: {
    Text("Your session will expire in 5 minutes. Would you like to stay signed in?")
}
```

---

### 26. Add Offline Support

**Priority:** Medium
**Effort:** 3-4 hours

**Current:** Can't use app without network
**Improved:** Allow cached credential usage offline

**Implementation:**
```swift
// Cache last successful auth timestamp
@AppStorage("lastAuthTimestamp") private var lastAuthTimestamp: TimeInterval = 0

// Allow offline usage if authenticated within last 7 days
private var canUseOffline: Bool {
    let lastAuth = Date(timeIntervalSince1970: lastAuthTimestamp)
    return Date().timeIntervalSince(lastAuth) < 604800 // 7 days
}

// In login flow
if !isOnline && canUseOffline {
    // Use cached credentials
    allowOfflineAccess()
} else if !isOnline {
    errorMessage = "You're offline. Connect to the internet to sign in."
}
```

---

## Accessibility Improvements

### 27. Add VoiceOver Announcements for Errors

**Priority:** Medium
**Effort:** 15 minutes

**Implementation:**
```swift
if let errorMessage {
    Text(errorMessage)
        .foregroundStyle(.red)
        .accessibilityLabel("Error")
        .accessibilityValue(errorMessage)
        .accessibilityAddTraits(.isAlert)
        .accessibilityHint("Double-check your credentials and connection, then try again.")
}
```

---

### 28. Add Haptic Feedback

**Priority:** Low
**Effort:** 10 minutes

**Implementation:**
```swift
#if os(iOS)
import UIKit

private func triggerHaptic(_ style: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(style)
}
#endif

// On error
#if os(iOS)
triggerHaptic(.error)
#endif

// On success
#if os(iOS)
triggerHaptic(.success)
#endif
```

---

## Implementation Plan

### Phase 1: Critical Fixes (Day 1) 🚨

**Goal:** Fix app-breaking and security-critical issues
**Time:** 2-3 hours

#### Must Complete:
1. ✅ Add `NSFaceIDUsageDescription` to Info.plist
2. ✅ Fix keychain security (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
3. ✅ Fix biometric policy (`.deviceOwnerAuthenticationWithBiometrics`)
4. ✅ Add keychain error throwing (stop silent failures)
5. ✅ Disable iCloud Keychain sync
6. ✅ Fix biometric lock timing (only lock on `.background`)

#### Testing:
- Run on physical device with Face ID
- Verify Face ID prompt appears correctly
- Test keychain security with device lock
- Test biometric locking behavior with notifications

#### Success Criteria:
- ✅ App doesn't crash on Face ID devices
- ✅ Tokens not accessible when device locked
- ✅ Face ID prompt appears (not passcode)
- ✅ App doesn't lock on brief interruptions

---

### Phase 2: Login UI Essentials (Day 2) ⭐

**Goal:** Core UX improvements for login screen
**Time:** 4-6 hours

#### Implement:
7. ✅ Password visibility toggle
8. ✅ Keyboard dismiss gesture
9. ✅ Clear buttons on text fields
10. ✅ Improved error styling
11. ✅ Loading state text
12. ✅ Fix password trimming inconsistency

#### Testing:
- Test password visibility toggle
- Test keyboard dismissal on tap
- Verify error styling in light/dark modes

#### Success Criteria:
- ✅ Users can see typed password
- ✅ Keyboard dismisses naturally
- ✅ Errors are clear and actionable

---

### Phase 3: Session Management (Day 3) ⏰

**Goal:** Implement reliable session handling
**Time:** 4-6 hours

#### Implement:
14. ✅ Token refresh mechanism
15. ✅ Session expiry warnings
16. ✅ Concurrent request protection
17. ✅ Better error differentiation (network vs auth)

#### Testing:
- Mock token expiration
- Test refresh timer behavior
- Test app backgrounding during refresh
- Verify concurrent login protection

#### Success Criteria:
- ✅ Tokens refresh automatically before expiry
- ✅ Users warned before session ends
- ✅ No race conditions in auth flow
- ✅ Clear distinction between error types

---

### Phase 4: Biometric Polish (Day 4) 🔑

**Goal:** Improve biometric authentication UX
**Time:** 3-4 hours

#### Implement:
18. ✅ Biometric error handling improvements
19. ✅ Passcode fallback option
20. ✅ Biometric availability monitoring
21. ✅ First-login biometric hint

#### Testing:
- Test with biometric disabled
- Test after too many failed attempts (lockout)
- Test passcode fallback flow
- Verify monitoring detects changes

#### Success Criteria:
- ✅ Clear error messages for all scenarios
- ✅ Graceful fallback when biometric fails
- ✅ App responds to biometric availability changes
- ✅ Users prompted to enable biometric

---

### Phase 5: Polish & Accessibility (Day 5) ✨

**Goal:** Final UX polish and accessibility
**Time:** 3-4 hours

#### Implement:
22. ✅ Real-time email validation
23. ✅ Success animation
24. ✅ VoiceOver improvements
25. ✅ Haptic feedback
26. ✅ Field icons (optional)

#### Testing:
- Full VoiceOver testing
- Test all animations
- Comprehensive manual testing

#### Success Criteria:
- ✅ Fully accessible to VoiceOver users
- ✅ Smooth animations and transitions
- ✅ Professional polish throughout

---

### Phase 6: Advanced Features (Future) 🚀

**Goal:** Optional enhancements for future consideration
**Time:** Variable

#### Consider:
29. ⏸️ Encryption layer over keychain (4-6 hours)
30. ⏸️ Apple Sign In / OAuth (6-8 hours)
31. ⏸️ Offline mode with cached credentials (3-4 hours)
32. ⏸️ Security event logging (2-3 hours)
33. ⏸️ Rate limiting UI feedback (1-2 hours)

---

## Testing Strategy

### Unit Tests Required

#### KeychainAuthStateStore Tests
```swift
// Test all error cases
- testSaveSuccess()
- testSaveFailure_DuplicateItem()
- testLoadSuccess()
- testLoadFailure_NotFound()
- testLoadFailure_InvalidData()
- testClearSuccess()
- testClearFailure_NotFound()
```

#### Authentication Flow Tests
```swift
- testSuccessfulSignIn()
- testFailedSignIn_InvalidCredentials()
- testFailedSignIn_NetworkError()
- testSignOut()
- testTokenRefresh()
- testTokenExpiration()
- testConcurrentSignInPrevention()
```

#### Biometric Tests
```swift
- testBiometricSuccess()
- testBiometricFailure_Cancelled()
- testBiometricFailure_Lockout()
- testBiometricFailure_NotAvailable()
- testPasscodeFallback()
- testBiometricMonitoring()
```

### Integration Tests Required

```swift
- testFullLoginFlow()
- testBiometricLockingFlow()
- testSessionRefreshFlow()
- testOfflineAuthFlow()
```

### Manual Testing Checklist

#### Login Screen
- [ ] Email validation shows correct icons
- [ ] Password visibility toggle works
- [ ] Clear buttons clear fields
- [ ] Keyboard dismisses on outside tap
- [ ] Tab order correct (macOS)
- [ ] Error messages display correctly
- [ ] Loading state shows progress
- [ ] Success animation plays

#### Biometric Authentication
- [ ] Face ID prompt appears on device
- [ ] Touch ID prompt appears on device
- [ ] Passcode fallback works
- [ ] Error messages accurate
- [ ] Settings toggle enables/disables
- [ ] App locks on backgrounding
- [ ] App doesn't lock on notifications
- [ ] Works after device restart

#### Session Management
- [ ] Token refreshes before expiry
- [ ] Expiry warning appears
- [ ] Expired session logs out
- [ ] Network errors handled gracefully
- [ ] Offline mode works (if implemented)

#### Accessibility
- [ ] VoiceOver announces all elements
- [ ] VoiceOver announces errors
- [ ] All buttons have labels
- [ ] Works with large text sizes
- [ ] Works with increased contrast mode
- [ ] Works with reduce motion enabled

#### Security
- [ ] Tokens not accessible when locked
- [ ] Tokens don't sync to iCloud
- [ ] Face ID description present
- [ ] Keychain errors reported
- [ ] No sensitive data in logs

---

## File Reference Guide

### Core Authentication Files

#### `ios/sideBar/sideBar/Services/Auth/`
- **SupabaseAuthAdapter.swift** - Main auth service, handles sign in/out
- **AuthSession.swift** - Auth state management
- **KeychainAuthStateStore.swift** - Secure credential storage

#### `ios/sideBar/sideBar/Views/Auth/`
- **LoginView.swift** - Login screen UI
- **BiometricLockView.swift** - Biometric unlock screen

#### `ios/sideBar/sideBar/App/`
- **AppEnvironment.swift** - App-wide state, auth state propagation
- **ServiceContainer.swift** - Dependency injection
- **ContentView.swift** - Root view, auth routing

#### Configuration
- **Info.plist** - App configuration, privacy descriptions
- **sideBarApp.swift** - App entry point

### Files to Create

#### New Views
- `Views/Auth/SecureFieldWithToggle.swift` - Password visibility toggle component

#### New Services
- `Services/Auth/BiometricMonitor.swift` - Monitor biometric availability
- `Services/Auth/SessionRefreshManager.swift` - Handle token refresh

#### Tests
- `sideBarTests/Auth/SupabaseAuthAdapterTests.swift`
- `sideBarTests/Auth/BiometricAuthenticationTests.swift`
- `sideBarTests/Auth/SessionManagementTests.swift`

---

## Risk Assessment

### High Risk Items

1. **Keychain Security Changes**
   - Risk: Could lock out existing users if migration fails
   - Mitigation: Implement careful migration with fallback
   - Test extensively before release

2. **Biometric Policy Change**
   - Risk: Users without biometric setup could be locked out
   - Mitigation: Implement graceful fallback, clear error messages
   - Provide passcode alternative

3. **Token Refresh Implementation**
   - Risk: Refresh failures could cause mass logouts
   - Mitigation: Extensive testing, gradual rollout
   - Monitor refresh success rates

### Medium Risk Items

4. **Session Timing Changes**
   - Risk: Could annoy users or reduce security
   - Mitigation: Make configurable, gather user feedback
   - Monitor analytics for logout patterns

### Low Risk Items

5. **UI Improvements**
   - Risk: Minor visual bugs, layout issues
   - Mitigation: Standard QA testing
   - Easy to fix post-release

---

## Success Metrics

### Security Metrics
- **Zero** keychain access from locked state
- **Zero** crashes related to Face ID
- **<1%** keychain operation failures
- **100%** token refresh success rate (excluding network errors)

### UX Metrics
- **<5 second** average login time
- **>90%** biometric authentication success rate
- **Zero** false lockouts (users locked out incorrectly)

### Quality Metrics
- **>80%** unit test coverage for auth code
- **100%** integration test coverage for critical flows
- **WCAG AA** accessibility compliance
- **Zero** critical bugs in production

---

## Rollout Plan

### Pre-Release
1. Complete Phase 1 (critical fixes)
2. Complete Phase 2 (login UI)
3. Complete Phase 3 (session management)
4. Internal testing with TestFlight
5. Fix critical bugs
6. Complete Phase 4 & 5

### Release v1
- All critical and high priority items
- Core UX improvements
- Comprehensive testing complete

### Post-Release
- Monitor crash reports
- Monitor authentication analytics
- Gather user feedback
- Plan Phase 6 (advanced features)

### Release v2
- Advanced features based on feedback
- Additional polish
- Performance optimizations

---

## Conclusion

This implementation plan addresses critical security vulnerabilities, UX gaps, and missing features in the authentication system. The phased approach ensures:

1. **Critical issues resolved first** - No app crashes or major security holes
2. **Core UX improvements next** - Users can successfully log in with a smooth, intuitive experience
3. **Polish and advanced features last** - Professional experience without delaying launch

**Total Estimated Time:** 3-5 days for core implementation (Phases 1-5)

**Recommended Minimum for Launch:** Complete Phases 1-3 (critical fixes + login UI + session management)

The authentication system will be secure, reliable, and provide an excellent user experience after completing these improvements.
