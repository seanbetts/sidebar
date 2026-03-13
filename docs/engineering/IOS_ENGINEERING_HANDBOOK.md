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
- `SENTRY_DSN` (optional reserved key; retained in the config surface, but the Apple bootstrap seam is currently inert)
- `R2_ENDPOINT`
- `R2_BUCKET`
- `R2_FAVICON_BUCKET`
- `R2_FAVICON_PUBLIC_BASE_URL`

Notes:
- Non-production runtime paths fail fast when required configuration is missing or invalid.
- Non-production builds do not silently fall back to production API endpoints.
- The Apple Sentry seam remains main-app-only. Share extension, widgets, and Safari targets remain excluded.
- The Apple Sentry bootstrap is intentionally inert in the current release cycle, so Debug, XCTest, and Release/TestFlight runs all skip Apple SDK startup.

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
python3 scripts/check_ios_doc_comments.py
python3 scripts/check_ios_architecture_boundaries.py
scripts/check-ios-warning-gate.sh
scripts/test-ios.sh
```

`scripts/test-ios.sh` defaults to serial execution when the lane includes `sideBarUITests` (for simulator stability), unless `IOS_PARALLEL_TESTING_ENABLED` is explicitly set.

CI workflow (`.github/workflows/ios-ci.yml`):

- Runs on two self-hosted runners on the developer machine:
  - `ios` runner: iPad and iPhone simulator test lanes (sequential).
  - `mac` runner: macOS native test lane, quality checks, and hard gates.
- Triggers: push to `dev` branch only (path-filtered to `ios/**` and CI scripts), plus manual `workflow_dispatch`.
- Quality job (parallel with test matrix):
  - SwiftLint
  - iOS doc-comment coverage check
  - Architecture boundary check
- Test matrix (parallel with quality job):
  - iPad lane: UI tests only, coverage disabled.
  - iPhone lane: all tests except UI tests, coverage enabled.
  - macOS lane: unit tests only, coverage disabled.
- Hard gates (runs after both quality and test matrix complete):
  - Per-target coverage thresholds and baseline-drop enforcement via `scripts/check_ios_quality_gates.py`.
  - First-party iOS target warning gate via `scripts/check_ios_quality_gates.py` warning policy.
  - Uses iPhone lane xcresult only.

Pre-push hook (`.git/hooks/pre-push`):

- Blocks pushes to `main` unless `scripts/test-ios.sh` passes locally.
- Local `main` pushes run `scripts/test-ios.sh` in dedicated pre-push simulator mode.
- The hook auto-creates and reuses `sideBar PrePush iPad`, storing its UDID in `.git/sidebar-pre-push/simulator-udid`.
- Blocks pushes to `main` unless `scripts/check-main-linear-history.sh` passes:
  - pushed `main` tip must match local `dev` tip
  - push range may not include merge commits
  - non-fast-forward updates to `main` are rejected
- Pushes to `dev` and other branches are unblocked.
- Self-hosted runner lanes keep their existing iPad, iPhone, and macOS split.
- Guards against broken builds reaching Xcode Cloud.
- Expensive iOS warning/cert gates are manual pre-commit hooks so normal `dev` pushes stay fast.

Recommended release command:

```bash
scripts/release-main.sh
```

This keeps `main` linear by promoting the published `origin/dev` tip with a fast-forward-only merge. It does not rewrite `dev` history. If you want an explicit local iOS preflight before promotion, run:

```bash
scripts/release-main.sh --run-ios-tests
```

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
- `SENTRY_DSN` may still be present in the environment to preserve config compatibility, but current Apple builds ignore it because the bootstrap seam is inert.
- `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, and `SENTRY_CLI_VERSION` are not used by the current Apple build path.
- Xcode Cloud handles `main` branch builds for distribution.

## Apple Sentry Status

- Runtime bootstrap still lives in `ios/sideBar/sideBar/App/SentryBootstrap.swift` and is invoked from both app delegates.
- `SentryBootstrap.startIfConfigured(...)` is currently a deliberate no-op that preserves the app launch seam without linking the Apple Sentry SDK.
- The `sentry-cocoa` package, `Sentry` product linkage, and `Upload Sentry dSYMs` build phase were removed to reduce Apple package-resolution risk before release.
- `ios/sideBar/ci_scripts/upload_sentry_dsyms.sh` is now an explicit disabled placeholder rather than an active release step.
- Any future Apple Sentry reintroduction should start with a new design/plan pass rather than reactivating the old upload flow ad hoc.

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
- Active/historical iOS implementation plans: `docs/superpowers/plans/`

## Maintenance Rule

Any PR that changes iOS setup, architecture boundaries, runtime configuration keys, or CI quality gates must update this handbook in the same change.
