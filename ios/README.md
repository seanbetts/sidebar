# iOS App (SwiftUI)

This directory contains the production Apple-platform app and Xcode project.

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
`/Users/sean/Coding/sideBar/ios/ENVIRONMENT.md` for required keys and setup.
