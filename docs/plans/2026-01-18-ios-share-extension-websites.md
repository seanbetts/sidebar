# iOS Share Extension (Websites Only)

## Goal
Add a minimal share sheet extension that saves a shared URL via the websites quick-save API and then closes. No polling and no auto-open.

## Scope
- URL-only share extension (max 1 URL).
- Fire-and-close flow with success/error UI.
- No job status polling.

## Plan
1. Add shared auth access
   - Update `KeychainAuthStateStore` to support a shared keychain access group/service.
   - Add Keychain Sharing + App Group entitlements to main app + extension.
2. Add share extension target (Xcode)
   - Create Share Extension target.
   - Activation rule: URL only, max count 1.
3. Implement share extension runtime
   - Minimal environment: API base URL + `WebsitesAPI`.
   - Extract URL from `NSExtensionItem`.
   - Call `POST /api/v1/websites/quick-save`.
   - Show loading/success/error UI and close extension.
4. Main app behavior
   - No app open or auto-navigation required.
   - Websites appear next app launch as usual.

## Out of Scope
- Polling job status.
- Opening the saved website from the extension.
- File or image sharing.
