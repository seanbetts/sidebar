# iOS Extensions, Widgets, App Intents, and Siri Plan
**Project:** sideBar iOS App
**Document Version:** 1.2
**Date:** 2026-01-31
**Estimated Total Effort:** 4-5 weeks (phased, shippable milestones)

---

## Executive Summary

This plan consolidates the iOS Share Extension, Live Activities, Widgets, App Intents, and Siri integration into a single, phased roadmap. It builds on the existing ShareExtension architecture and the App Group/Keychain/IPC infrastructure already present in the codebase.

**Phases:**
1. ✅ Share Extension (URLs, images, files) - **COMPLETE**
2. Live Activities for upload progress
3. ✅ Widgets + App Intents + Siri (core) - **COMPLETE** (All content types)
4. ✅ Widgets polish - **PARTIAL** (Lock screen complete, background refresh complete)

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

## Phase 1: Share Extension (Week 1) ✅ COMPLETE

**Goal:** Share URLs, images, and files into sideBar
**Status:** Complete (2026-01-26)

### Tasks
1. ✅ Confirm `ShareExtension` target has App Group and Keychain access groups configured.
2. ✅ Verify `ShareExtensionEnvironment` uses `AppGroupConfiguration` for shared tokens.
3. ✅ Implement URL, image, and file handling in `ShareViewController`.
4. ✅ Post share events via `ExtensionEventStore` for main app refresh.
5. ✅ Add minimal UI states (loading, success, error, progress).

### Implementation Details
- **ShareViewController.swift**: Complete rewrite with priority-based content detection (images → files → URLs)
- **ShareExtensionEnvironment.swift**: Added `uploadFile()` method for multipart form uploads
- **ShareProgressView.swift**: New progress bar UI for uploads
- **ExtensionEventStore.swift**: Extended with `fileSaved` and `imageSaved` event types, plus `fileId` and `filename` fields
- **MIME type detection**: Comprehensive support for 20+ file types (images, documents, media)

### Verification ✅
- ✅ Share URL from Safari saves website.
- ✅ Share image uploads file (converts to JPEG).
- ✅ Share PDF/documents uploads file.
- ✅ Unauthenticated shows user-friendly error.
- ✅ Events posted to ExtensionEventStore for main app refresh.

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

## Phase 3: Widgets + App Intents + Siri (Week 3) ✅ COMPLETE

**Goal:** Core widgets and App Intents (Siri + Shortcuts)
**Status:** All content type widgets complete (2026-01-31)

### Widget Foundation ✅ COMPLETE
- ✅ Created `sideBarWidgets` target with App Group and Keychain sharing.
- ✅ Added `WidgetDataManager` with generic type-safe storage architecture.
- ✅ Implemented deep linking via `sidebar://` URL scheme.

### Generic Widget Storage Architecture ✅ COMPLETE
The widget system now uses a generic, type-safe storage architecture supporting multiple content types:

**Protocols:**
- `WidgetStorable` - Protocol for widget data models (Codable, Identifiable, Equatable)
- `WidgetDataContainer` - Protocol for data containers with items, totalCount, lastUpdated

**Content Types (`WidgetContentType` enum):**
- `.tasks` - Today's tasks (implemented)
- `.notes` - Recent notes (models ready)
- `.websites` - Saved websites (models ready)
- `.files` - Recent files (models ready)

**Generic API:**
```swift
// Store data (type-safe)
WidgetDataManager.shared.store(data, for: .tasks)

// Load data (type-safe)
let data: WidgetTaskData = WidgetDataManager.shared.load(for: .tasks)

// Pending operations (widget → main app)
let op = WidgetPendingOperation(itemId: id, action: TaskWidgetAction.complete)
WidgetDataManager.shared.recordPendingOperation(op, for: .tasks)
```

### Widgets Implemented ✅

**Tasks:**
1. ✅ **TodayTasksWidget** - Shows today's tasks with completion buttons
2. ✅ **TaskCountWidget** - Compact task count display
3. ✅ **LockScreenTaskCountWidget** - Circular lock screen widget
4. ✅ **LockScreenTaskPreviewWidget** - Rectangular lock screen widget
5. ✅ **LockScreenInlineWidget** - Inline text lock screen widget

**Notes:**
6. ✅ **PinnedNotesWidget** - Shows pinned notes (small/medium/large)
7. ✅ **LockScreenNoteCountWidget** - Circular lock screen widget
8. ✅ **LockScreenNotePreviewWidget** - Rectangular lock screen widget
9. ✅ **LockScreenNotesInlineWidget** - Inline text lock screen widget

**Websites:**
10. ✅ **SavedSitesWidget** - Shows pinned websites (small/medium/large)
11. ✅ **LockScreenSiteCountWidget** - Circular lock screen widget
12. ✅ **LockScreenSitePreviewWidget** - Rectangular lock screen widget
13. ✅ **LockScreenSitesInlineWidget** - Inline text lock screen widget

**Files:**
14. ✅ **PinnedFilesWidget** - Shows pinned files with file type icons (small/medium/large)
15. ✅ **LockScreenFileCountWidget** - Circular lock screen widget
16. ✅ **LockScreenFilePreviewWidget** - Rectangular lock screen widget
17. ✅ **LockScreenFilesInlineWidget** - Inline text lock screen widget

### Widgets Remaining
1. Recent Conversations widget (not planned)

### App Intents Implemented ✅

**Tasks:**
1. ✅ `CompleteTaskIntent` - Marks task complete from widget
2. ✅ `OpenTodayIntent` - Opens app to Today view
3. ✅ `AddTaskIntent` - Opens app to add new task
4. ✅ `OpenTaskIntent` - Opens specific task

**Notes:**
5. ✅ `OpenNotesIntent` - Opens notes view
6. ✅ `CreateNoteIntent` - Opens app to create new note
7. ✅ `OpenNoteIntent` - Opens specific note

**Websites:**
8. ✅ `OpenWebsitesIntent` - Opens saved websites view
9. ✅ `QuickSaveIntent` - Saves URL to websites
10. ✅ `OpenWebsiteIntent` - Opens specific website

**Files:**
11. ✅ `OpenFilesIntent` - Opens files view
12. ✅ `OpenFileIntent` - Opens specific file

**General:**
13. ✅ `OpenScratchpadIntent` - Opens scratchpad
14. ✅ `StartChatIntent` - Starts new AI chat
15. ✅ `OpenChatIntent` - Opens specific chat

### App Intents Remaining
None - all planned intents implemented.

### Siri and Shortcuts ✅ COMPLETE
- ✅ Registered `SideBarShortcutsProvider` with Siri phrases for all content types:
  - Tasks: "Show my tasks", "Add a task"
  - Notes: "Show my notes", "Create a note"
  - Websites: "Show my saved websites", "Save this website"
  - Files: "Show my files"
  - General: "Open scratchpad", "Start a chat"

### Verification ✅
- ✅ Task widgets show cached data instantly.
- ✅ Deep links open correct destinations (`sidebar://tasks/today`, `sidebar://tasks/new`).
- ✅ Task completion from widget syncs to main app.
- ✅ Intents appear in Shortcuts app.

---

## Phase 4: Widgets Polish and System Integrations (Week 4) - PARTIAL ✅

**Goal:** Interactive widgets, lock screen, Spotlight, background refresh

### Tasks
1. Add interactive widgets (iOS 17) for scratchpad refresh and quick actions.
2. ✅ Add lock screen widgets (accessory families) - Complete for all content types.
3. Add Focus Filters for widget data filtering.
4. ✅ Add Spotlight indexing for notes, files, and websites - Complete.
5. ✅ Add background refresh to keep widget data current - Complete.
6. (Optional) Control Center widget for iOS 18+.

### Background Refresh Implementation ✅
Widget data is refreshed through multiple mechanisms:
- **Mutation triggers**: Widget data updates immediately when items are pinned/unpinned/modified
- **Push notifications**: All widget data refreshes when push notification received
- **Background task**: `BGAppRefreshTask` refreshes all widget data every 30 minutes
- **Timeline refresh**: Widgets request new timelines every 15 minutes
- **Task due date boundaries**: Task widgets create timeline entries at due date boundaries

### Spotlight Indexing Implementation ✅
CoreSpotlight integration enables system-wide search for notes, files, and websites:

**Files:**
- `ios/sideBar/sideBar/Services/Spotlight/SpotlightIndexer.swift` - Main indexer with protocol for testability

**Indexed Content:**
- **Notes**: Title, content (full text search), path components as keywords
- **Files**: Filename, category, file metadata
- **Websites**: Title, URL, domain

**Features:**
- Bulk indexing on list/tree load
- Individual indexing on item view/edit
- Automatic removal on delete
- Index cleared on sign out (privacy)
- Deep links: `sidebar://notes/{path}`, `sidebar://files/{id}`, `sidebar://websites/{id}`

**Integration Points:**
- `NotesStore.applyTreeUpdate()` - Bulk indexes notes from tree
- `NotesStore.applyNoteUpdate()` - Indexes individual note with full content
- `IngestionStore.applyListUpdate()` - Bulk indexes files
- `WebsitesStore.applyListUpdate()` - Bulk indexes websites
- `AppSceneDelegate.scene(_:continue:)` - Handles Spotlight tap deep links
- `AppEnvironment+Auth.refreshAuthState()` - Clears index on sign out

### Verification
- Interactive widget buttons work without opening the app.
- ✅ Lock screen widgets display correctly.
- ✅ Spotlight results open the app to the right location.
- ✅ Background refresh keeps widgets fresh.

---

## Shared Code and File Locations

### Share Extension (Complete)
- `ios/sideBar/ShareExtension/ShareViewController.swift` - Main extension controller with URL/image/file handling
- `ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift` - Auth, API client, and file upload
- `ios/sideBar/ShareExtension/ShareLoadingView.swift` - Loading state UI
- `ios/sideBar/ShareExtension/ShareSuccessView.swift` - Success state UI
- `ios/sideBar/ShareExtension/ShareErrorView.swift` - Error state UI
- `ios/sideBar/ShareExtension/ShareProgressView.swift` - Upload progress UI

### Shared Utilities
- `ios/sideBar/sideBar/Utilities/AppGroupConfiguration.swift` - App Group ID configuration
- `ios/sideBar/sideBar/Utilities/ExtensionEventStore.swift` - IPC between extension and main app
- `ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift` - Shared keychain access

### Spotlight Indexing
- `ios/sideBar/sideBar/Services/Spotlight/SpotlightIndexer.swift` - CoreSpotlight indexer with protocol

### Widget Storage Architecture (Main App)
- `ios/sideBar/sideBar/Utilities/WidgetStorable.swift` - Protocols for widget models
- `ios/sideBar/sideBar/Utilities/WidgetContentType.swift` - Content type enum with storage keys
- `ios/sideBar/sideBar/Utilities/WidgetPendingOperation.swift` - Generic pending operation types
- `ios/sideBar/sideBar/Utilities/WidgetDataManager.swift` - Generic storage + migration + deprecated wrappers

### Widget Extension (Implemented)
```
ios/sideBar/sideBarWidgets/
├── sideBarWidgets.entitlements
├── sideBarWidgetsBundle.swift          # Widget bundle registration
├── WidgetStorable.swift                # Shared protocols
├── WidgetContentType.swift             # Content type enum
├── WidgetPendingOperation.swift        # Pending operation types
├── WidgetDataManager.swift             # Lightweight read/record operations
├── WidgetModels.swift                  # All widget models (Task, Note, Website, File)
├── Providers/
│   ├── TodayTasksProvider.swift        # Timeline provider for task widgets
│   ├── PinnedNotesProvider.swift       # Timeline provider for notes widgets
│   ├── SavedSitesProvider.swift        # Timeline provider for website widgets
│   └── PinnedFilesProvider.swift       # Timeline provider for files widgets
├── Widgets/
│   ├── TodayTasksWidget.swift          # Main tasks widget (small/medium/large)
│   ├── TaskCountWidget.swift           # Compact task count
│   ├── LockScreenWidgets.swift         # Task lock screen variants
│   ├── PinnedNotesWidget.swift         # Notes widget (small/medium/large)
│   ├── LockScreenNotesWidgets.swift    # Notes lock screen variants
│   ├── SavedSitesWidget.swift          # Websites widget (small/medium/large)
│   ├── LockScreenSitesWidgets.swift    # Websites lock screen variants
│   └── PinnedFilesWidget.swift         # Files widget (small/medium/large)
└── Intents/
    └── TaskIntents.swift               # Task-related App Intents
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

1. ✅ ~~Confirm App Group IDs and entitlements for all targets.~~
2. ✅ ~~Verify Share Extension completeness.~~
3. ✅ ~~Build Tasks widgets with generic storage architecture.~~
4. ✅ ~~Add Notes/Websites/Files widgets using existing generic architecture.~~
5. ✅ ~~Add background refresh for widget data (BGAppRefreshTask + push notifications).~~
6. ✅ ~~Add lock screen widgets for Files.~~
7. ✅ ~~Add App Intents for all content types (notes, websites, files, chat, scratchpad).~~
8. ✅ ~~Add Spotlight indexing for notes, files, and websites.~~
9. **Next:** Implement Live Activities with upload progress (Phase 2).
10. Add interactive widgets (iOS 17) for quick actions.

### Adding a New Widget Type

To add widgets for notes, websites, or files:

1. **Create timeline provider** in `sideBarWidgets/Providers/`:
   ```swift
   struct RecentNotesProvider: TimelineProvider {
     func getTimeline(...) {
       let data: WidgetNoteData = WidgetDataManager.shared.load(for: .notes)
       // Build timeline entries
     }
   }
   ```

2. **Create widget view** in `sideBarWidgets/Widgets/`:
   ```swift
   struct RecentNotesWidget: Widget {
     var body: some WidgetConfiguration {
       StaticConfiguration(kind: "RecentNotesWidget", provider: RecentNotesProvider()) { entry in
         RecentNotesWidgetView(entry: entry)
       }
     }
   }
   ```

3. **Update ViewModel** to push data to widgets:
   ```swift
   // In NotesViewModel after loading notes
   let widgetNotes = recentNotes.prefix(5).map { WidgetNote(from: $0) }
   let data = WidgetNoteData(notes: Array(widgetNotes), totalCount: allNotes.count)
   WidgetDataManager.shared.store(data, for: .notes)
   ```

4. **Register widget** in `sideBarWidgetsBundle.swift`:
   ```swift
   var body: some Widget {
     TodayTasksWidget()
     // ... existing widgets
     RecentNotesWidget()  // Add new widget
   }
   ```

5. **Add deep link handling** (if needed) in `AppEnvironment+DeepLink.swift`.
