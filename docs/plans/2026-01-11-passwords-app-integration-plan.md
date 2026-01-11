# Plan: Passwords app integration (Apple ecosystem)

## Goal
Enable full iCloud Passwords/Passwords.app integration for sideBar sign-in across iOS/iPadOS/macOS by configuring Associated Domains and web credentials.

## Prerequisites
- Decide the canonical web domain for sign-in (production or staging).
- Access to DNS/hosting to serve the `apple-app-site-association` (AASA) file over HTTPS.

## Phase 1 — App configuration (iOS/iPadOS/macOS)
- Add Associated Domains entitlement to `ios/sideBar/sideBar/sideBar.entitlements`:
  - `webcredentials:<domain>`
  - `applinks:<domain>` (optional, if you want universal links later)
- Ensure Xcode target has Associated Domains capability enabled.
- Confirm the sign-in UI uses:
  - `.textContentType(.username)` for the email/username field
  - `.textContentType(.password)` for the password field

## Phase 2 — AASA file setup (server-side)
- Host `https://<domain>/.well-known/apple-app-site-association` (no extension).
- AASA should include:
  - `webcredentials.apps` with the team ID + bundle ID
  - `applinks.details` if universal links are desired
- Serve with `Content-Type: application/json` and no redirects.

## Phase 3 — Validation
- Validate the AASA file:
  - `curl -I https://<domain>/.well-known/apple-app-site-association`
  - `curl https://<domain>/.well-known/apple-app-site-association | jq .`
- Install a development build on device and confirm:
  - Password AutoFill suggestions appear on the login view
  - Passwords app can store and autofill credentials for the domain

## Phase 4 — Hardening & documentation
- Add a short internal doc with the AASA file contents and host requirements.
- If you use staging + prod domains, list both in entitlements and document rollout steps.

## Deliverables
- Updated entitlements with `webcredentials:<domain>`.
- AASA file deployed to the domain.
- Verified Password AutoFill in iOS/iPadOS/macOS.
