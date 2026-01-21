# iOS Extensions, Widgets, App Intents, and Siri Plan
**Project:** sideBar iOS App
**Document Version:** 1.0
**Date:** 2026-01-13
**Estimated Total Effort:** 4-5 weeks (phased, shippable milestones)

---

## Executive Summary

This plan consolidates the iOS Share Extension, Live Activities, Widgets, App Intents, and Siri integration into a single, phased roadmap. It builds on the existing ShareExtension architecture and the App Group/Keychain/IPC infrastructure already present in the codebase.

**Phases:**
1. Share Extension (URLs, images, files)
2. Live Activities for upload progress
3. Widgets + App Intents + Siri (core)
4. Widgets polish: interactive widgets, lock screen, Spotlight, background refresh

---

## Current Architecture (Already Implemented)

- **App Groups configuration:** `AppGroupConfiguration` (uses `APP_GROUP_ID` in xcconfig; default derives from bundle ID).
- **Keychain sharing:** `KeychainAuthStateStore` supports shared access groups.
- **IPC:** `ExtensionEventStore` (UserDefaults-based, drain-after-read).
- **Share Extension pattern:** `ShareExtensionEnvironment` (fail-fast init, shared auth + API base URL).

These should be used as templates for Widgets and Intents.

---

## Prerequisites and Configuration

### App Groups and Entitlements
- App Group ID is driven by `APP_GROUP_ID` in `ios/sideBar/Config/SideBar.local.xcconfig.example`.
- Ensure `sideBar.entitlements`, `ShareExtension.entitlements`, and the new Widgets entitlements all include the same App Group and Keychain access group.

### Info.plist and Capabilities
- `CFBundleURLTypes` for `sidebar://` deep linking.
- `NSSiriUsageDescription` for Siri.
- `BGTaskSchedulerPermittedIdentifiers` for widget refresh.
- Live Activities require `NSSupportsLiveActivities` and Push Notifications capability if remote updates are used.

---

## Phase 1: Share Extension (Week 1)

**Goal:** Share URLs, images, and files into sideBar
**Status:** Core infrastructure already exists; verify and finalize implementation.

### Tasks
1. Confirm `ShareExtension` target has App Group and Keychain access groups configured.
2. Verify `ShareExtensionEnvironment` uses `AppGroupConfiguration` for shared tokens.
3. Implement URL, image, and file handling in `ShareViewController` (if not complete).
4. Post share events via `ExtensionEventStore` for main app refresh.
5. Add minimal UI states (loading, success, error).

### Verification
- Share URL from Safari saves website.
- Share image/PDF uploads file.
- Offline or unauthenticated shows user-friendly error.

---

## Phase 2: Live Activities for Uploads (Week 2)

**Goal:** Show upload progress using Live Activities (iOS 16.1+)

### Tasks
1. Add notification permission flow and device token handling.
2. Add ActivityKit models and Live Activity UI widget.
3. Add LiveActivityManager to manage activity lifecycle.
4. Extend `IngestionAPI` to report upload progress via delegate.
5. Connect progress updates to LiveActivityManager in `IngestionViewModel`.
6. Hook realtime ingestion job updates to update or complete activities.

### Verification
- Upload starts a Live Activity.
- Progress updates in Dynamic Island and lock screen.
- Completion and failure states are rendered correctly.

---

## Phase 3: Widgets + App Intents + Siri (Week 3)

**Goal:** Core widgets and App Intents (Siri + Shortcuts)

### Widget Foundation
- Create `sideBarWidgets` target (iOS 17+ recommended).
- Add `WidgetEnvironment` mirroring `ShareExtensionEnvironment`.
- Add `WidgetDataManager` for cached data in App Group UserDefaults.

### Widgets (Core)
1. Recent Conversations widget.
2. Recent Notes widget.
3. Scratchpad widget (read-only for MVP).

### App Intents (Core)
1. `StartChatIntent` (opens app).
2. `CreateNoteIntent` (no UI required).
3. `QuickSaveIntent` (saves URL).
4. `OpenScratchpadIntent` (opens app).

### Siri and Shortcuts
- Register `AppShortcutsProvider` with Siri phrases.
- Ensure `NSUserActivityTypes` contains all intent identifiers.

### Verification
- Widgets show cached data instantly, then refresh with API data.
- Deep links open correct destinations.
- Intents appear in Shortcuts and respond to Siri phrases.

---

## Phase 4: Widgets Polish and System Integrations (Week 4)

**Goal:** Interactive widgets, lock screen, Spotlight, background refresh

### Tasks
1. Add interactive widgets (iOS 17) for scratchpad refresh and quick actions.
2. Add lock screen widgets (accessory families).
3. Add Focus Filters for widget data filtering.
4. Add Spotlight indexing for conversations and notes.
5. Add background refresh to keep widget data current.
6. (Optional) Control Center widget for iOS 18+.

### Verification
- Interactive widget buttons work without opening the app.
- Lock screen widgets display correctly.
- Spotlight results open the app to the right location.
- Background refresh keeps widgets fresh.

---

## Shared Code and File Locations

### Existing (Reference Patterns)
- `ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift`
- `ios/sideBar/sideBar/Utilities/AppGroupConfiguration.swift`
- `ios/sideBar/sideBar/Utilities/ExtensionEventStore.swift`
- `ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift`

### New Targets (Planned)
```
ios/sideBar/sideBarWidgets/
├── sideBarWidgets.entitlements
├── WidgetsBundle.swift
├── WidgetEnvironment.swift
├── WidgetDataManager.swift
├── Providers/
├── Widgets/
└── Intents/
```

---

## Risks and Mitigations

- **Auth in extensions**: Ensure shared keychain + access groups in all targets.
- **Widget data staleness**: Cache in App Group defaults and refresh on app changes.
- **Deep link correctness**: Centralize `onOpenURL` handling in main app.
- **Live Activities coverage**: Provide lock screen UI and graceful fallback on non-Dynamic Island devices.

---

## Testing Checklist (Condensed)

- Share Extension: URL, image, file, offline, unauthenticated.
- Live Activities: start, update, completion, failure, background.
- Widgets: cached load, refresh, deep link, sign-out state.
- Intents/Siri: discoverability, parameter handling, and correct routing.
- Lock screen/Spotlight: render and open correctly.

---

## Next Steps

1. Confirm App Group IDs and entitlements for all targets.
2. Verify Share Extension completeness.
3. Implement Live Activities with upload progress.
4. Build core widgets and App Intents.
5. Polish with interactive widgets, lock screen, and Spotlight.
