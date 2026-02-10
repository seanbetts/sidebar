---
title: "iOS Engineering Handbook"
description: "Canonical setup, architecture, and operational guide for sideBar Apple-platform development."
---

# iOS Engineering Handbook

This is the canonical iOS/macOS engineering document for sideBar.

- Source of truth for Apple-platform setup, architecture, and operations.
- Applies to: `ios/sideBar` app target, extensions, shared framework, and Apple test targets.
- Last reviewed: `2026-02-10`.

## Scope and Project Layout

- Project root: `ios/sideBar`
- Main app target: `ios/sideBar/sideBar`
- Shared framework: `ios/sideBar/sideBarShared`
- Share extension: `ios/sideBar/ShareExtension`
- Widgets extension: `ios/sideBar/sideBarWidgets`
- Safari extensions: `ios/sideBar/sideBar Safari Extension*`
- Tests: `ios/sideBar/sideBarTests`, `ios/sideBar/sideBarUITests`

## Platform and Tooling Requirements

- Xcode with iOS/macOS 26 SDK support.
- Apple simulator runtimes used in CI:
  - `iPad Pro 13-inch (M5)` (iPadOS 26.2)
  - `iPhone 17 Pro` (iOS 26.2)
  - `macOS` (arm64, macOS 26)
- Swift toolchain version from project settings: `Swift 5`.

## Local Setup

1. Copy `ios/sideBar/Config/SideBar.local.xcconfig.example` to `ios/sideBar/Config/SideBar.local.xcconfig`.
2. Fill in all required runtime keys.
3. Open `ios/sideBar/sideBar.xcodeproj` in Xcode.
4. Ensure Debug base configuration points to `Config/SideBar.xcconfig`.
5. Build and run the `sideBar` scheme.

## Runtime Configuration (Required Keys)

Runtime values come from `.xcconfig` and are exposed via Info.plist build settings.

- `API_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_GROUP_ID`
- `KEYCHAIN_ACCESS_GROUP`
- `KEYCHAIN_SERVICE`
- `R2_ENDPOINT`
- `R2_BUCKET`
- `R2_FAVICON_BUCKET`
- `R2_FAVICON_PUBLIC_BASE_URL`

Notes:
- Non-production runtime paths fail fast when required configuration is missing or invalid.
- Non-production builds do not silently fall back to production API endpoints.

## Architecture Summary

Primary pattern is MVVM with an explicit Store layer:

- `Views`: SwiftUI rendering and user interaction.
- `ViewModels`: `@MainActor` state orchestration and user intent handling.
- `Stores`: cache-first data coordination, realtime mapping, and persistence integration.
- `Services`: network/auth/cache/realtime/upload/persistence infrastructure.

Core data flow:

1. UI triggers view-model action.
2. View model delegates to store/service APIs.
3. Store updates `@Published` state from cache/network/realtime.
4. SwiftUI reacts to published state changes.

## Architecture Boundaries (CI-Enforced)

Layering constraints are enforced by `scripts/check_ios_architecture_boundaries.py`:

- `Services` cannot depend on `Stores`, `ViewModels`, or `Views`.
- `Stores` cannot depend on `ViewModels` or `Views`.
- `ViewModels` cannot depend on `Views`.

Do not bypass these checks with cross-layer shortcuts.

## Testing and Quality Gates

Local validation commands:

```bash
swiftlint --config ios/sideBar/.swiftlint.yml
python scripts/check_ios_doc_comments.py
python scripts/check_ios_architecture_boundaries.py
scripts/test-ios.sh
```

CI workflow:

- Workflow: `.github/workflows/ios-ci.yml`
- Quality job:
  - SwiftLint
  - iOS doc-comment coverage check
  - Architecture boundary check
- Test matrix:
  - iPad lane
  - iPhone lane
  - macOS lane
- Hard gates:
  - Per-target coverage thresholds and baseline-drop enforcement via `scripts/check_ios_quality_gates.py`

## Xcode Cloud Notes

- Script: `ios/sideBar/ci_scripts/ci_post_clone.sh`
- It generates `SideBar.local.xcconfig` from environment variables.
- Missing required values fail the build early.

## Extension Reliability Expectations

- Share, widget, and Safari extension families should each have deterministic XCTest coverage.
- Keep extension-specific contract tests focused on:
  - message/deeplink shape validation
  - auth/config edge cases
  - retry/recovery behavior

## Documentation Map

Use this handbook as primary reference.

- Quick project orientation: `ios/README.md`
- Environment key detail: `ios/ENVIRONMENT.md`
- Legacy architecture page (deprecated pointer): `docs/IOS_ARCHITECTURE.md`
- Active/historical iOS implementation plans: `docs/plans/`

## Maintenance Rule

Any PR that changes iOS setup, architecture boundaries, runtime configuration keys, or CI quality gates must update this handbook in the same change.
