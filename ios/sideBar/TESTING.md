# Apple Testing

## Apple test taxonomy

The shared iOS/macOS app uses one Apple test taxonomy across all feature areas.

- `Logic`: deterministic shared-code tests
- `Surface`: mounted views, app-environment wiring, persistence, platform-hosted behavior, and broader integration coverage
- `UI Smoke`: tiny end-to-end app checks only

This applies equally to Notes, Files, Chat, Tasks, Websites, Skills, app-shell code, and extensions.

## Branch policy

- `dev` should run `Logic`
- `main` should run `Logic`, `Surface`, and `UI Smoke`

## Lane routing

- Use the `sideBarLogicHost` scheme with `AppleFast` for logic tests (runs on macOS, no simulator needed).
- The `sideBar` scheme includes `sideBarTests`, while `AppleFast` targets `sideBarLogicTests`.
- Running `AppleFast` directly through the `sideBar` scheme causes Xcode to union those test bundles, build both `sideBar` and `sideBarLogicHost`, and risk duplicate `sideBar.swiftmodule` outputs.
- CI uses `sideBarLogicHost` directly for the Logic lane.

Current websites and extension split:

- `sideBarLogicTests/WebsitesViewModelTests` runs in `AppleFast`.
- `sideBarTests/WebsitesStoreTests` stays in `AppleStateful`.
- `sideBarTests/AppEnvironmentDeepLinkTests` stays in `AppleStateful`.
- `ShareExtensionTests/ShareExtensionCoverageTests` stays in `AppleExtensions`.

## Placement rules

Choose the lowest appropriate Apple test layer first.

- default new Apple tests to `logic`
- choose `surface` only when the logic layer cannot prove the behavior
- choose `ui_smoke` only for true end-to-end coverage
- gate live UI smoke tests with `SIDEBAR_RUN_LIVE_UI_TESTS=1` before reading credentials or launching the app

Support files, harnesses, fixtures, and helpers may live beside tests, but they are not test cases.

## Naming guidance

Use names that make the layer obvious when possible:

- `*LogicTests.swift` for deterministic shared logic
- `*SurfaceTests.swift` or `*IntegrationTests.swift` for mounted/platform/persistence coverage
- `*UITests.swift` for true app-level smoke checks

Existing files do not need to be renamed immediately, but new Apple tests should follow the taxonomy deliberately.
