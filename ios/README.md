# iOS App (SwiftUI)

This directory contains the production Apple-platform app and Xcode project.

Canonical documentation lives in:
- `/Users/sean/Coding/sideBar/docs/engineering/IOS_ENGINEERING_HANDBOOK.md`

Use this file as a quick orientation page only.

## Project Layout
- `sideBar/`: Xcode project root.
- `sideBar/sideBar/`: main iOS/macOS SwiftUI app target.
- `sideBar/sideBarShared/`: shared framework used by app and extensions.
- `sideBar/ShareExtension/`: share extension target.
- `sideBar/sideBarWidgets/`: widget extension target.
- `sideBar/sideBar Safari Extension*`: Safari extension targets.
- `sideBar/sideBarTests/`: unit/integration test target.
- `sideBar/sideBarUITests/`: UI test target.
- `sideBar/Config/`: build configuration (`SideBar.xcconfig`, local overrides).

## Runtime Configuration
Runtime keys are loaded through build settings and Info.plist keys. See
`/Users/sean/Coding/sideBar/ios/ENVIRONMENT.md` for key details and
`/Users/sean/Coding/sideBar/docs/engineering/IOS_ENGINEERING_HANDBOOK.md` for full setup and operations guidance.

## Apple Sentry Status
- The Apple app no longer links `sentry-cocoa` in the current release cycle.
- `/Users/sean/Coding/sideBar/ios/sideBar/sideBar/App/SentryBootstrap.swift` remains as an inert local seam, and `startIfConfigured(...)` currently returns `false` without starting an SDK client.
- `SENTRY_DSN` is still part of the Apple config surface for now, but current Apple builds ignore it.
- `/Users/sean/Coding/sideBar/ios/sideBar/ci_scripts/upload_sentry_dsyms.sh` is an explicit disabled placeholder pending any future reintroduction.
