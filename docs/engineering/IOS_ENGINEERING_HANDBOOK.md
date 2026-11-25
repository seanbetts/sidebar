---
title: "iOS Engineering Handbook"
description: "Canonical setup, architecture, and operational guide for sideBar Apple-platform development."
---

# iOS Engineering Handbook

This is the canonical iOS/macOS engineering document for sideBar.

- Source of truth for Apple-platform setup, architecture, and operations.
- Applies to: `ios/sideBar` app target, extensions, shared framework, and Apple test targets.
- Last reviewed: `2026-03-12`.

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
  - `iPad Pro 13-inch (M5)` (iPadOS 26.0)
  - `iPhone 17 Pro` (iOS 26.0)
  - `macOS` (arm64, macOS 26)
- Swift toolchain version from project settings: `Swift 5`.

## Local Setup

For a signed build, select your own Apple development team. If you deploy the web app, replace `YOURTEAMID` in both Apple App Site Association files under `frontend/static` and configure the matching associated domains in Xcode.

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
- `ASSOCIATED_DOMAINS` (for example `webcredentials:app.trysidebar.ai`)
- `SENTRY_DSN` (optional runtime key, when present it enables Apple Sentry startup for the app and Apple extension surfaces)
- `R2_ENDPOINT`
- `R2_BUCKET`
- `R2_FAVICON_BUCKET`
- `R2_FAVICON_PUBLIC_BASE_URL`

Notes:
- Non-production runtime paths fail fast when required configuration is missing or invalid.
- Non-production builds do not silently fall back to production API endpoints.
- Apple Sentry is wired behind `SENTRY_DSN`. If the DSN is unset, the app and extensions skip SDK startup.
- The repo currently links Sentry into the main app, widget extension, share extension, and Safari extension targets.

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

## Workspace Engine and Agent Surfaces

The Apple app now uses a unified workspace model that supports both built-in sections and agent-driven dynamic surfaces.

- Canonical state: `WorkspaceStore` + `WorkspaceState` (`ios/sideBar/sideBar/App/WorkspaceStore.swift`, `WorkspaceModels.swift`).
- Modes:
  - `core`: built-in content sections (notes, websites, files, tasks, chat, etc.).
  - `agent`: dynamic assistant surfaces rendered in workspace panes.
- Pane model:
  - `primary` and `secondary` panes can each render either built-in descriptors or `agentSurface` descriptors.
  - Existing UX remains preserved (pane swapping, expand/fullscreen behavior, compact/split layouts).
- Stream integration:
  - Chat SSE `workspace_patch` events are parsed by `ChatWorkspacePatchParser` and dispatched as typed `WorkspaceAction`s.
- Rendering:
  - `AgentWorkspaceSurfaceView` renders agent surface types (`markdown`, `table`, `chart`, `map`, `form`, `actionPanel`).
  - Title-bar affordances are consistent with other content headers (expand, `...` menu, close/refresh where capability-enabled).
  - Surface menu actions are payload-driven (`context_menu_actions`).
- Reopen behavior:
  - Chat tool results can expose "Show ..." workspace action buttons for reopening previously presented surfaces.

## Architecture Boundaries

Layering constraints:

- `Services` cannot depend on `Stores`, `ViewModels`, or `Views`.
- `Stores` cannot depend on `ViewModels` or `Views`.
- `ViewModels` cannot depend on `Views`.

Do not bypass these constraints with cross-layer shortcuts.

## Testing and Quality

Local validation commands:

```bash
swiftlint --config ios/sideBar/.swiftlint.yml
python3 scripts/check_ios_doc_comments.py

# Logic tests (fast, no simulator)
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarLogicHost -testPlan AppleFast \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

# Coverage lane (manual, no simulator)
xcodebuild test -project ios/sideBar/sideBar.xcodeproj \
  -scheme sideBarLogicHost -testPlan AppleCoverage \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

CI workflow (`ci/workflows/ios-ci.yml`):

- Runs on a self-hosted Mac runner.
- `dev` branch: SwiftLint + doc comments + AppleFast logic tests on macOS (no simulator).
- Manual dispatch can run the AppleCoverage plan and upload the `.xcresult` bundle without slowing normal pushes.
- `main` branch: AppleFast logic tests on macOS + AppleUI + AppleExtensions on iOS simulator.
- Manual dispatch available for any lane combination.

Pre-push hook (`.git/hooks/pre-push`):

- Runs lint checks only (SwiftLint, doc comments). No test execution.
- Blocks pushes to `main` unless `scripts/check-main-linear-history.sh` passes:
  - pushed `main` tip must match local `dev` tip
  - push range may not include merge commits
  - non-fast-forward updates to `main` are rejected
- Pushes to `dev` and other branches are unblocked.
- Guards against broken builds reaching Xcode Cloud.

Recommended release command:

```bash
scripts/release-main.sh
```

This keeps `main` linear by promoting the published `origin/dev` tip with a fast-forward-only merge. It does not rewrite `dev` history. If you want an explicit local iOS preflight before promotion, run:

```bash
scripts/release-main.sh --run-ios-tests
```

## macOS Widget Notes

Widget verification is handled by CI workflows and the release script. No separate widget scripts are needed for day-to-day development.

## Self-Hosted Runner Setup

Two GitHub Actions runners run locally on the developer machine:

1. `ios-runner` (label: `ios`, installed at `~/Coding/actions-runner-ios`): handles iPad and iPhone simulator lanes.
2. `mac-runner` (label: `mac`, installed at `~/Coding/actions-runner-mac`): handles macOS lane, quality checks, and hard gates.

Management:

```bash
# Start/stop runners
cd ~/Coding/actions-runner-ios && ./svc.sh start   # or stop, status
cd ~/Coding/actions-runner-mac && ./svc.sh start   # or stop, status
```

Runners only need to be active when you want CI to process pushes to `dev`.

## Xcode Cloud Notes

- Script: `ios/sideBar/ci_scripts/ci_post_clone.sh`
- It generates `SideBar.local.xcconfig` from environment variables.
- Missing required values fail the build early.
- `SENTRY_DSN` controls runtime startup. Empty or unresolved values keep the Apple app and extensions from starting Sentry.
- `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, and `SENTRY_CLI_VERSION` are used by the Apple dSYM upload path when present.
- Xcode Cloud handles `main` branch builds for distribution.

## Apple Sentry Status

- Runtime bootstrap still lives in `ios/sideBar/sideBar/App/SentryBootstrap.swift` and is invoked from both app delegates.
- `SentryBootstrap.startIfConfigured(...)` is active. It starts the SDK only when `SENTRY_DSN` resolves to a non-empty value and the process is not running tests or previews.
- `ExtensionSentryBootstrap.startIfConfigured(...)` is also active for the widget, share extension, and Safari extension surfaces when they are built with a non-empty DSN.
- The current Apple bootstrap enables app hang tracking, auto session tracking, network tracking, and trace propagation targets derived from the configured backend hosts.
- The repo uses a vendored `Vendor/Sentry/Sentry.xcframework` instead of Swift Package Manager for Apple builds.
- `ios/sideBar/ci_scripts/upload_sentry_dsyms.sh` remains an active build-path helper when the Sentry auth/project environment variables are present.

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

## Maintenance Rule

Any PR that changes iOS setup, architecture boundaries, runtime configuration keys, or CI workflows must update this handbook in the same change.
