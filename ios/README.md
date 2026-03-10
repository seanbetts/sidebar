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

## Sentry
- The main `sideBar` app target initializes Sentry only for Release builds when `SENTRY_DSN` is present.
- Xcode Cloud can inject `SENTRY_DSN` through `/Users/sean/Coding/sideBar/ios/sideBar/ci_scripts/ci_post_clone.sh`.
- Release archives can upload dSYMs through `/Users/sean/Coding/sideBar/ios/sideBar/ci_scripts/upload_sentry_dsyms.sh` when `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, and `SENTRY_PROJECT` are configured.
