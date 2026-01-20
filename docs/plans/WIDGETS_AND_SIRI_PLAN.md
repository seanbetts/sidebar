# Comprehensive Implementation Plan: Widgets, App Intents & Siri Integration for sideBar iOS

## Executive Summary

This plan outlines the implementation of **Widgets**, **App Intents**, and **Siri integration** for the sideBar iOS app, following the proven architecture patterns from the existing ShareExtension. The implementation is divided into 4 incremental phases, each shippable independently.

**Total Duration:** 4 weeks
**Pattern Template:** ShareExtension architecture (proven, battle-tested)
**Key Infrastructure:** Already in place (App Groups, Keychain sharing, IPC)

---

## Architecture Foundation (Already Implemented)

### ✅ Existing Infrastructure Ready to Leverage

1. **App Groups Configuration**
   - App Group ID: `group.ai.sidebar.sidebar`
   - Already used by ShareExtension
   - File: `Utilities/AppGroupConfiguration.swift`

2. **Keychain Sharing**
   - AES-GCM encrypted storage
   - Cross-target access via access groups
   - File: `Services/Auth/KeychainAuthStateStore.swift`

3. **Extension Pattern (ShareExtension as Template)**
   - `ShareExtensionEnvironment`: Throwing initializer, fail-fast design
   - Uses `AppGroupConfiguration` for all shared resources
   - Pattern: Initialize APIs with shared auth token

4. **IPC Mechanism**
   - `ExtensionEventStore`: UserDefaults-based event passing
   - Fire-and-forget with drain-after-read pattern
   - File: `Utilities/ExtensionEventStore.swift`

5. **Action System**
   - `ShortcutAction` enum: 35+ navigation/action types
   - `ShortcutContext` enum: 7 contexts (universal, chat, notes, etc.)
   - Ready foundation for App Intents

### 📋 API Capabilities Available

- **ConversationsAPI**: create(), list(), get(), addMessage(), search()
- **NotesAPI**: createNote(), listTree(), search(), updateNote(), pinNote()
- **WebsitesAPI**: save(), quickSave(), list(), search(), pin()
- **MemoriesAPI**: create(), list(), update(), delete()
- **ScratchpadAPI**: get(), update(), clear()
- **IngestionAPI**: upload(), list(), getMeta()

---

## Phase 1: Foundation & Basic Widgets (Week 1)

### Goals
- Create widget extension target
- Implement 2 static widgets (Recent Conversations, Recent Notes)
- Set up deep linking
- Enable widget data caching

### Implementation Steps

#### 1.1 Create Widget Extension Target

**Action:** Create new Widget Extension target in Xcode
- Product Name: `sideBarWidgets`
- Bundle ID: `ai.sidebar.sidebar.Widgets`
- iOS Deployment: 17.0+
- Embed in: sideBar

**New Files:**
```
ios/sideBar/sideBarWidgets/
├── Info.plist
├── sideBarWidgets.entitlements
├── WidgetsBundle.swift
├── WidgetEnvironment.swift
├── WidgetDataManager.swift
├── Providers/
│   ├── RecentConversationsProvider.swift
│   └── RecentNotesProvider.swift
└── Widgets/
    ├── RecentConversationsWidget.swift
    └── RecentNotesWidget.swift
```

#### 1.2 Configure Entitlements

**File:** `sideBarWidgets/sideBarWidgets.entitlements`
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.ai.sidebar.sidebar</string>
</array>
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)ai.sidebar.sidebar.Widgets</string>
    <string>$(AppIdentifierPrefix)ai.sidebar.sidebar</string>
</array>
```

**File:** `sideBar/sideBar.entitlements` (UPDATE)
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.ai.sidebar.sidebar</string>
</array>
```

#### 1.3 Create WidgetEnvironment (Follow ShareExtension Pattern)

**File:** `sideBarWidgets/WidgetEnvironment.swift`

**Pattern:** Exactly mirrors `ShareExtensionEnvironment.swift`
```swift
@MainActor
final class WidgetEnvironment {
    let apiClient: APIClient
    let conversationsAPI: ConversationsAPI
    let notesAPI: NotesAPI
    let scratchpadAPI: ScratchpadAPI

    init() throws {
        let keychain = KeychainAuthStateStore(
            service: AppGroupConfiguration.keychainService,
            accessGroup: AppGroupConfiguration.keychainAccessGroup
        )

        guard let token = try keychain.loadAccessToken(), !token.isEmpty else {
            throw WidgetError.notAuthenticated
        }

        let baseUrl = try WidgetEnvironment.apiBaseURL()
        let config = APIClientConfig(
            baseUrl: baseUrl,
            accessTokenProvider: { token }
        )
        self.apiClient = APIClient(config: config)
        self.conversationsAPI = ConversationsAPI(client: apiClient)
        self.notesAPI = NotesAPI(client: apiClient)
        self.scratchpadAPI = ScratchpadAPI(client: apiClient)
    }

    private static func apiBaseURL() throws -> URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: override) {
            return url
        }
        guard let url = URL(string: "https://sidebar-api.fly.dev/api/v1") else {
            throw WidgetError.invalidBaseUrl
        }
        return url
    }
}

enum WidgetError: LocalizedError {
    case notAuthenticated
    case invalidBaseUrl
    case dataUnavailable
}
```

#### 1.4 Create Widget Data Manager (Caching Layer)

**File:** `sideBarWidgets/WidgetDataManager.swift`

**Purpose:** Cache widget data in app group UserDefaults for instant loading
```swift
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()

    private let conversationsKey = "widget_recent_conversations"
    private let notesKey = "widget_recent_notes"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var userDefaults: UserDefaults? {
        guard let suiteName = AppGroupConfiguration.appGroupId else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    public func saveConversations(_ conversations: [Conversation]) {
        guard let defaults = userDefaults,
              let data = try? encoder.encode(conversations) else { return }
        defaults.set(data, forKey: conversationsKey)
        defaults.synchronize()
    }

    public func loadConversations() -> [Conversation]? {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: conversationsKey) else { return nil }
        return try? decoder.decode([Conversation].self, from: data)
    }

    // Similar methods for notes, scratchpad
}
```

#### 1.5 Create Recent Conversations Widget

**File:** `sideBarWidgets/Providers/RecentConversationsProvider.swift`

**Key Pattern:** Try cache first (instant), then fetch fresh
```swift
struct RecentConversationsProvider: TimelineProvider {
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        // Load from cache immediately (instant display)
        if let cached = WidgetDataManager.shared.loadConversations() {
            completion(Entry(date: Date(), conversations: Array(cached.prefix(5)), error: nil))
            return
        }
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            do {
                let environment = try WidgetEnvironment()
                let conversations = try await environment.conversationsAPI.list()

                // Cache for next load
                WidgetDataManager.shared.saveConversations(conversations)

                let entry = Entry(date: Date(), conversations: Array(conversations.prefix(5)), error: nil)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                // Fallback to cached data on error
                let cached = WidgetDataManager.shared.loadConversations() ?? []
                let entry = Entry(date: Date(), conversations: cached, error: error.localizedDescription)
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
                completion(timeline)
            }
        }
    }
}
```

**File:** `sideBarWidgets/Widgets/RecentConversationsWidget.swift`
```swift
struct RecentConversationsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentConversationsWidget", provider: RecentConversationsProvider()) { entry in
            RecentConversationsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Chats")
        .description("View your recent conversations")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentConversationsView: View {
    let entry: RecentConversationsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Chats", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            ForEach(entry.conversations.prefix(3)) { conversation in
                Link(destination: URL(string: "sidebar://chat/\(conversation.id)")!) {
                    VStack(alignment: .leading) {
                        Text(conversation.title).font(.subheadline).lineLimit(1)
                        if let preview = conversation.firstMessage {
                            Text(preview).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
```

#### 1.6 Create Recent Notes Widget

**File:** `sideBarWidgets/Providers/RecentNotesProvider.swift` (similar pattern)
**File:** `sideBarWidgets/Widgets/RecentNotesWidget.swift`

**Note Extraction Logic:**
```swift
private func extractRecentNotes(from nodes: [FileNode]) -> [FileNode] {
    var results: [FileNode] = []
    for node in nodes {
        if node.type == .file && node.archived != true {
            results.append(node)
        }
        if let children = node.children {
            results.append(contentsOf: extractRecentNotes(from: children))
        }
    }
    return results.sorted { ($0.modified ?? 0) > ($1.modified ?? 0) }
}
```

#### 1.7 Deep Linking Setup

**File:** `sideBar/sideBarApp.swift` (MODIFY)
```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .environmentObject(environment)
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }
}

private func handleDeepLink(_ url: URL) {
    guard url.scheme == "sidebar" else { return }

    switch url.host {
    case "chat":
        let id = url.lastPathComponent
        environment.commandSelection = .chat
        Task { await environment.chatViewModel.openConversation(id: id) }

    case "notes":
        let path = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        environment.commandSelection = .notes
        Task { await environment.notesViewModel.selectNote(path: path) }

    default: break
    }
}
```

**File:** `sideBar/Info.plist` (ADD)
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>sidebar</string></array>
        <key>CFBundleURLName</key>
        <string>ai.sidebar.sidebar</string>
    </dict>
</array>
```

#### 1.8 Background Widget Data Updates

**File:** `sideBar/App/AppEnvironment.swift` (ADD METHOD)
```swift
private func updateWidgetData() {
    Task {
        if let conversations = try? await container.conversationsAPI.list() {
            WidgetDataManager.shared.saveConversations(conversations)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// Call after:
// - Creating/updating conversations
// - Creating/updating notes
// - Network reconnection (refreshOnReconnect)
```

### Phase 1 Verification

**Testing Checklist:**
- [ ] Widget extension builds successfully
- [ ] Both widgets appear in widget gallery
- [ ] Widgets display cached data instantly (getSnapshot)
- [ ] Widgets fetch fresh data (getTimeline)
- [ ] Tapping widget items opens correct screen in app
- [ ] Widgets handle auth errors gracefully (show "Sign in" message)
- [ ] Widgets work in all sizes (small, medium, large)
- [ ] Background refresh updates widget data

**Critical Files:**
- Template: `/Users/sean.betts/Coding/sideBar/ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift`
- Config: `/Users/sean.betts/Coding/sideBar/ios/sideBar/sideBar/Utilities/AppGroupConfiguration.swift`
- Auth: `/Users/sean.betts/Coding/sideBar/ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift`

---

## Phase 2: App Intents Core (Week 2)

### Goals
- Implement App Intents framework
- Create 4 core intents (StartChat, CreateNote, QuickSave, OpenScratchpad)
- Enable Siri voice commands
- Add Shortcuts app integration
- Create App Entities for queryable objects

### Implementation Steps

#### 2.1 App Entities (Queryable Objects)

**File:** `sideBarWidgets/Intents/AppEntities/NoteEntity.swift`
```swift
import AppIntents

struct NoteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static var defaultQuery = NoteEntityQuery()

    var id: String
    var name: String
    var path: String
    var content: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: path)
    }
}

struct NoteEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NoteEntity] {
        let environment = try WidgetEnvironment()
        var results: [NoteEntity] = []
        for id in identifiers {
            if let note = try? await environment.notesAPI.getNote(id: id) {
                results.append(NoteEntity(id: note.id, name: note.name, path: note.path, content: note.content))
            }
        }
        return results
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        let environment = try WidgetEnvironment()
        let tree = try await environment.notesAPI.listTree()
        // Extract and return recent notes (up to 10)
        return extractRecentNotes(from: tree.children).prefix(10).map {
            NoteEntity(id: $0.path, name: $0.name, path: $0.path, content: nil)
        }
    }
}
```

**Similar files:**
- `ConversationEntity.swift` - For querying conversations
- `WebsiteEntity.swift` - For querying saved websites

#### 2.2 Core App Intents

**File:** `sideBarWidgets/Intents/Actions/StartChatIntent.swift`
```swift
import AppIntents

struct StartChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Chat"
    static var description = IntentDescription("Start a new conversation in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Conversation Title", default: "New Chat")
    var title: String

    @Parameter(title: "Initial Message", requestValueDialog: "What would you like to say?")
    var message: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a chat called \(\.$title)") {
            \.$message
        }
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let environment = try WidgetEnvironment()
        let conversation = try await environment.conversationsAPI.create(title: title)

        if let message = message, !message.isEmpty {
            let messageCreate = ConversationMessageCreate(
                id: UUID().uuidString,
                role: "user",
                content: message,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            _ = try await environment.conversationsAPI.addMessage(
                conversationId: conversation.id,
                message: messageCreate
            )
        }

        // Update widget cache
        WidgetDataManager.shared.saveConversations(try await environment.conversationsAPI.list())
        WidgetCenter.shared.reloadAllTimelines()

        // Deep link to conversation
        return .result(opensIntent: OpenURLIntent(url: URL(string: "sidebar://chat/\(conversation.id)")!))
    }
}
```

**File:** `sideBarWidgets/Intents/Actions/CreateNoteIntent.swift`
```swift
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Create a new note in sideBar")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note Title")
    var title: String

    @Parameter(title: "Content", requestValueDialog: "What would you like to write?")
    var content: String?

    @Parameter(title: "Folder Path")
    var folder: String?

    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> {
        let environment = try WidgetEnvironment()
        let request = NoteCreateRequest(content: content ?? "", title: title, path: nil, folder: folder)
        let note = try await environment.notesAPI.createNote(request: request)

        WidgetCenter.shared.reloadTimelines(ofKind: "RecentNotesWidget")

        return .result(
            value: NoteEntity(id: note.id, name: note.name, path: note.path, content: note.content),
            dialog: "Created note '\(title)'"
        )
    }
}
```

**File:** `sideBarWidgets/Intents/Actions/QuickSaveIntent.swift`
```swift
struct QuickSaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Save Website"

    @Parameter(title: "URL", requestValueDialog: "What URL would you like to save?")
    var url: String

    @Parameter(title: "Custom Title")
    var customTitle: String?

    func perform() async throws -> some IntentResult {
        let environment = try WidgetEnvironment()
        guard URL(string: url) != nil else {
            throw IntentError.message("Invalid URL")
        }

        _ = try await environment.websitesAPI.quickSave(url: url, title: customTitle)
        ExtensionEventStore.shared.recordWebsiteSaved(url: url)

        return .result(dialog: "Saved website")
    }
}
```

**File:** `sideBarWidgets/Intents/Actions/OpenScratchpadIntent.swift`
```swift
struct OpenScratchpadIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Scratchpad"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(url: URL(string: "sidebar://scratchpad")!))
    }
}
```

#### 2.3 App Shortcuts Provider (Siri Phrases)

**File:** `sideBarWidgets/Intents/AppShortcutsProvider.swift`
```swift
import AppIntents

struct SideBarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartChatIntent(),
            phrases: [
                "Start a chat in \(.applicationName)",
                "New conversation in \(.applicationName)",
                "Chat with \(.applicationName)"
            ],
            shortTitle: "Start Chat",
            systemImageName: "bubble.left.and.bubble.right"
        )

        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New note in \(.applicationName)",
                "Take a note in \(.applicationName)"
            ],
            shortTitle: "Create Note",
            systemImageName: "note.text"
        )

        AppShortcut(
            intent: QuickSaveIntent(),
            phrases: [
                "Save a website in \(.applicationName)",
                "Quick save in \(.applicationName)"
            ],
            shortTitle: "Save Website",
            systemImageName: "link"
        )

        AppShortcut(
            intent: OpenScratchpadIntent(),
            phrases: ["Open scratchpad in \(.applicationName)"],
            shortTitle: "Scratchpad",
            systemImageName: "note"
        )
    }
}
```

#### 2.4 Info.plist Configuration

**File:** `sideBarWidgets/Info.plist` (ADD)
```xml
<key>NSUserActivityTypes</key>
<array>
    <string>StartChatIntent</string>
    <string>CreateNoteIntent</string>
    <string>QuickSaveIntent</string>
    <string>OpenScratchpadIntent</string>
</array>
```

**File:** `sideBar/Info.plist` (ADD)
```xml
<key>NSSiriUsageDescription</key>
<string>Use Siri to create notes, start chats, and access sideBar features.</string>
```

### Phase 2 Verification

**Testing Checklist:**
- [ ] All intents appear in Shortcuts app
- [ ] "Hey Siri, create a note in sideBar" works
- [ ] "Hey Siri, start a chat in sideBar" works
- [ ] "Hey Siri, save a website in sideBar" works
- [ ] Intent parameters can be customized in Shortcuts app
- [ ] Intents work from Spotlight search
- [ ] App entities can be queried (type "note" in Shortcuts)
- [ ] Deep links from intents open correct screens

**Siri Phrases to Test:**
1. "Hey Siri, create a note in sideBar called Meeting Notes"
2. "Hey Siri, start a chat in sideBar"
3. "Hey Siri, save a website in sideBar"
4. "Hey Siri, open scratchpad in sideBar"

---

## Phase 3: Interactive Widgets & Advanced Intents (Week 3)

### Goals
- Add interactive buttons to widgets (iOS 17)
- Create Scratchpad widget with refresh button
- Implement SearchNotesIntent
- Add Quick Actions widget
- Enable Focus Filter integration

### Implementation Steps

#### 3.1 Interactive Scratchpad Widget

**File:** `sideBarWidgets/Widgets/ScratchpadWidget.swift`
```swift
import WidgetKit
import SwiftUI
import AppIntents

struct ScratchpadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScratchpadWidget", provider: ScratchpadProvider()) { entry in
            ScratchpadView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Scratchpad")
        .description("Quick access to your scratchpad")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ScratchpadView: View {
    let entry: ScratchpadEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Scratchpad", systemImage: "note")
                    .font(.headline)

                Spacer()

                // Interactive refresh button (iOS 17+)
                Button(intent: RefreshScratchpadIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .tint(.blue)
            }

            Text(entry.content.isEmpty ? "Your scratchpad is empty" : entry.content)
                .font(.caption)
                .lineLimit(8)

            // Interactive open button
            Button(intent: OpenScratchpadIntent()) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("Open")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }
}

// Button intent
struct RefreshScratchpadIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Scratchpad"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "ScratchpadWidget")
        return .result()
    }
}
```

#### 3.2 Quick Actions Widget

**File:** `sideBarWidgets/Widgets/QuickActionsWidget.swift`
```swift
struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickActionsWidget", provider: QuickActionsProvider()) { entry in
            QuickActionsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Actions")
        .description("Quick shortcuts to common actions")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickActionsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Button(intent: StartChatIntent()) {
                Label("New Chat", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(intent: CreateNoteIntent()) {
                Label("New Note", systemImage: "note.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(intent: OpenScratchpadIntent()) {
                Label("Scratchpad", systemImage: "note")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
```

#### 3.3 Search Intents

**File:** `sideBarWidgets/Intents/Actions/SearchNotesIntent.swift`
```swift
struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Notes"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Search Query", requestValueDialog: "What would you like to search for?")
    var query: String

    @Parameter(title: "Limit", default: 10)
    var limit: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        let environment = try WidgetEnvironment()
        let results = try await environment.notesAPI.search(query: query, limit: limit)

        var entities: [NoteEntity] = []
        for node in results {
            if let note = try? await environment.notesAPI.getNote(id: node.path) {
                entities.append(NoteEntity(id: note.id, name: note.name, path: note.path, content: note.content))
            }
        }

        return .result(value: entities, dialog: "Found \(entities.count) notes matching '\(query)'")
    }
}
```

#### 3.4 Focus Filter Integration

**File:** `sideBarWidgets/Intents/Actions/FocusFilterIntent.swift`
```swift
struct SideBarFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set sideBar Focus"

    @Parameter(title: "Show Only Pinned Items")
    var showPinnedOnly: Bool

    @Parameter(title: "Hide Archived")
    var hideArchived: Bool

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: AppGroupConfiguration.appGroupId) else {
            throw IntentError.message("Unable to save focus settings")
        }

        defaults.set(showPinnedOnly, forKey: "focus_showPinnedOnly")
        defaults.set(hideArchived, forKey: "focus_hideArchived")
        defaults.synchronize()

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

**Update Providers:** Modify `RecentNotesProvider` and `RecentConversationsProvider` to respect focus:
```swift
// In getTimeline:
let defaults = UserDefaults(suiteName: AppGroupConfiguration.appGroupId)
let showPinnedOnly = defaults?.bool(forKey: "focus_showPinnedOnly") ?? false
let hideArchived = defaults?.bool(forKey: "focus_hideArchived") ?? true

// Apply filters to data
```

### Phase 3 Verification

**Testing Checklist:**
- [ ] Scratchpad widget shows live content
- [ ] Interactive refresh button works (reloads data)
- [ ] Interactive open button launches app
- [ ] Quick Actions widget buttons work
- [ ] SearchNotesIntent returns accurate results
- [ ] Focus filters affect widget content correctly
- [ ] All interactive widgets work without opening app

---

## Phase 4: Lock Screen & Polish (Week 4)

### Goals
- Lock screen widgets (iOS 16+)
- Spotlight integration
- Intent donations for Siri suggestions
- Background refresh
- Control Center widgets (iOS 18)

### Implementation Steps

#### 4.1 Lock Screen Widgets

**File:** `sideBarWidgets/Widgets/UnreadChatsWidget.swift`
```swift
struct UnreadChatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UnreadChatsWidget", provider: UnreadChatsProvider()) { entry in
            UnreadChatsLockScreenView(entry: entry)
        }
        .configurationDisplayName("Unread Chats")
        .description("Number of unread conversations")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct UnreadChatsLockScreenView: View {
    let entry: UnreadChatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title3)
                    Text("\(entry.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
        case .accessoryInline:
            Text("\(entry.count) chats")
        default:
            EmptyView()
        }
    }
}
```

#### 4.2 Spotlight Integration

**File:** `sideBar/Services/SpotlightIndexer.swift` (NEW)
```swift
import CoreSpotlight
import UniformTypeIdentifiers

final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    func indexConversations(_ conversations: [Conversation]) {
        var items: [CSSearchableItem] = []

        for conversation in conversations {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = conversation.title
            attributeSet.contentDescription = conversation.firstMessage
            attributeSet.keywords = ["chat", "conversation", "sideBar"]

            let item = CSSearchableItem(
                uniqueIdentifier: "conversation-\(conversation.id)",
                domainIdentifier: "conversations",
                attributeSet: attributeSet
            )
            items.append(item)
        }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error = error {
                print("Spotlight indexing error: \(error)")
            }
        }
    }

    func indexNotes(_ notes: [FileNode]) {
        // Similar implementation for notes
    }
}
```

**Integration:** Call `SpotlightIndexer.shared.indexConversations()` after loading conversations in `AppEnvironment`

#### 4.3 Intent Donations (Siri Suggestions)

**File:** `sideBar/Services/IntentDonationManager.swift` (NEW)
```swift
import Intents

final class IntentDonationManager {
    static let shared = IntentDonationManager()

    func donateCreateNote(title: String) {
        let intent = CreateNoteIntent()
        intent.title = title

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate intent: \(error)")
            }
        }
    }

    func donateStartChat(title: String) {
        let intent = StartChatIntent()
        intent.title = title

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { _ in }
    }
}
```

**Usage:** Call after user actions:
```swift
// In ChatViewModel after creating conversation:
IntentDonationManager.shared.donateStartChat(title: conversation.title)

// In NotesViewModel after creating note:
IntentDonationManager.shared.donateCreateNote(title: note.name)
```

#### 4.4 Background Refresh

**File:** `sideBar/App/AppLaunchDelegate.swift` (MODIFY)
```swift
import BackgroundTasks

final class AppLaunchDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundTasks()
        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "ai.sidebar.sidebar.widget-refresh",
            using: nil
        ) { task in
            self.handleWidgetRefresh(task: task as! BGAppRefreshTask)
        }
    }

    private func handleWidgetRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        Task {
            do {
                let environment = try WidgetEnvironment()
                let conversations = try await environment.conversationsAPI.list()
                WidgetDataManager.shared.saveConversations(conversations)

                WidgetCenter.shared.reloadAllTimelines()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
    }

    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "ai.sidebar.sidebar.widget-refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

**File:** `sideBar/Info.plist` (ADD)
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>ai.sidebar.sidebar.widget-refresh</string>
</array>
```

#### 4.5 Control Center Widget (iOS 18+)

**File:** `sideBarWidgets/Intents/Controls/QuickChatControl.swift`
```swift
#if compiler(>=6.0)
import AppIntents

@available(iOS 18.0, *)
struct QuickChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickChatControl") {
            ControlWidgetButton(action: StartChatIntent()) {
                Label("New Chat", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .displayName("Quick Chat")
    }
}
#endif
```

### Phase 4 Verification

**Testing Checklist:**
- [ ] Lock screen widgets display correctly
- [ ] Spotlight search returns sideBar items
- [ ] Tapping Spotlight results opens correct screen
- [ ] Siri suggestions appear after repeated actions
- [ ] Background refresh updates widget data
- [ ] Control Center widget works (iOS 18)
- [ ] All widget families work (circular, inline, small, medium, large)

---

## Configuration Summary

### Entitlements Changes

**Main App (`sideBar/sideBar.entitlements`)**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.ai.sidebar.sidebar</string>
</array>
<key>com.apple.developer.siri</key>
<true/>
```

**Widget Extension (`sideBarWidgets/sideBarWidgets.entitlements`)**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.ai.sidebar.sidebar</string>
</array>
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)ai.sidebar.sidebar.Widgets</string>
    <string>$(AppIdentifierPrefix)ai.sidebar.sidebar</string>
</array>
```

### Info.plist Updates

**Main App (`sideBar/Info.plist`)**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>sidebar</string></array>
    </dict>
</array>
<key>NSSiriUsageDescription</key>
<string>Use Siri to create notes, start chats, and access sideBar features.</string>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>ai.sidebar.sidebar.widget-refresh</string>
</array>
```

**Widget Extension (`sideBarWidgets/Info.plist`)**
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
</dict>
<key>NSUserActivityTypes</key>
<array>
    <string>StartChatIntent</string>
    <string>CreateNoteIntent</string>
    <string>QuickSaveIntent</string>
    <string>OpenScratchpadIntent</string>
    <string>SearchNotesIntent</string>
</array>
```

---

## Target Dependencies & Shared Code

### Shared Files (Add to Widget Target)

**Required for Widget Extension:**
1. **Models:**
   - All models from `sideBar/Models/`
   - `ChatModels.swift`, `NoteModels.swift`, `ConversationModels.swift`, `WebsiteModels.swift`

2. **Network:**
   - `Services/Network/APIClient.swift`
   - `Services/Network/ConversationsAPI.swift`
   - `Services/Network/NotesAPI.swift`
   - `Services/Network/ScratchpadAPI.swift`
   - `Services/Network/WebsitesAPI.swift`

3. **Utilities:**
   - `Utilities/AppGroupConfiguration.swift`
   - `Utilities/ExtensionEventStore.swift`

4. **Authentication:**
   - `Services/Auth/KeychainAuthStateStore.swift`
   - `Services/Auth/AuthSession.swift`

**How to Share:**
- In Xcode, select each file → File Inspector → Target Membership
- Enable checkbox for `sideBarWidgets` target

---

## File Structure Overview

```
ios/sideBar/
├── sideBarWidgets/                                   [NEW TARGET]
│   ├── Info.plist
│   ├── sideBarWidgets.entitlements
│   ├── WidgetsBundle.swift
│   ├── WidgetEnvironment.swift                       [Pattern: ShareExtensionEnvironment]
│   ├── WidgetDataManager.swift                       [Caching layer]
│   ├── Providers/
│   │   ├── RecentConversationsProvider.swift
│   │   ├── RecentNotesProvider.swift
│   │   ├── ScratchpadProvider.swift
│   │   ├── QuickActionsProvider.swift
│   │   └── UnreadChatsProvider.swift
│   ├── Widgets/
│   │   ├── RecentConversationsWidget.swift
│   │   ├── RecentNotesWidget.swift
│   │   ├── ScratchpadWidget.swift
│   │   ├── QuickActionsWidget.swift
│   │   └── UnreadChatsWidget.swift
│   └── Intents/
│       ├── AppEntities/
│       │   ├── NoteEntity.swift
│       │   ├── ConversationEntity.swift
│       │   └── WebsiteEntity.swift
│       ├── Actions/
│       │   ├── StartChatIntent.swift
│       │   ├── CreateNoteIntent.swift
│       │   ├── QuickSaveIntent.swift
│       │   ├── OpenScratchpadIntent.swift
│       │   ├── SearchNotesIntent.swift
│       │   └── FocusFilterIntent.swift
│       ├── AppShortcutsProvider.swift
│       └── Controls/
│           └── QuickChatControl.swift               [iOS 18+]
├── sideBar/
│   ├── sideBar.entitlements                         [MODIFIED]
│   ├── Info.plist                                   [MODIFIED]
│   ├── sideBarApp.swift                             [MODIFIED - deep links]
│   ├── App/
│   │   ├── AppEnvironment.swift                     [MODIFIED - widget updates]
│   │   └── AppLaunchDelegate.swift                  [MODIFIED - background refresh]
│   └── Services/
│       ├── SpotlightIndexer.swift                   [NEW]
│       └── IntentDonationManager.swift              [NEW]
```

---

## Critical Implementation References

### Pattern Templates (Reference These Files)

1. **Extension Environment Pattern:**
   - `/Users/sean.betts/Coding/sideBar/ios/sideBar/ShareExtension/ShareExtensionEnvironment.swift`
   - Copy initialization pattern exactly for `WidgetEnvironment`

2. **App Groups & Configuration:**
   - `/Users/sean.betts/Coding/sideBar/ios/sideBar/sideBar/Utilities/AppGroupConfiguration.swift`
   - Use for all shared resource access

3. **Keychain Authentication:**
   - `/Users/sean.betts/Coding/sideBar/ios/sideBar/sideBar/Services/Auth/KeychainAuthStateStore.swift`
   - Follow pattern for widget authentication

4. **IPC Communication:**
   - `/Users/sean.betts/Coding/sideBar/ios/sideBar/sideBar/Utilities/ExtensionEventStore.swift`
   - Use for widget→app communication

5. **API Clients:**
   - `/Users/sean.betts/Coding/sideBar/ios/sideBar/sideBar/Services/Network/ConversationsAPI.swift`
   - Reference for API patterns in intents

---

## Success Metrics

### User Capabilities After Implementation

**Siri Commands:**
- "Hey Siri, create a note in sideBar called Meeting Notes"
- "Hey Siri, start a chat in sideBar"
- "Hey Siri, save a website in sideBar"
- "Hey Siri, search notes in sideBar for project"
- "Hey Siri, open scratchpad in sideBar"

**Widget Features:**
- See recent conversations on home screen
- See recent notes on home screen
- Tap widget to open specific conversation/note
- Tap "New Chat" button directly from widget (no app open)
- See scratchpad content in widget
- Refresh scratchpad with button tap

**Shortcuts Integration:**
- Create automated workflows combining sideBar actions
- Schedule note creation at specific times
- Save websites automatically based on triggers
- Chain intents together (e.g., create note → add to chat)

**Spotlight Integration:**
- Search for "project notes" → Find sideBar notes
- Search for "client chat" → Find sideBar conversations
- Tap result → Opens directly in app

**Lock Screen:**
- See unread chat count
- See latest note title
- Quick access to new chat button

---

## Testing Strategy

### Phase-by-Phase Testing

**Phase 1 (Widgets):**
1. Build widget extension successfully
2. Add both widgets to home screen
3. Verify instant display (cached data)
4. Verify fresh data fetch (15min timeline)
5. Tap widget items → Opens correct screen
6. Sign out → Widgets show "Sign in" message
7. Sign back in → Widgets refresh with data

**Phase 2 (App Intents):**
1. Open Shortcuts app → Find sideBar intents
2. Test each intent manually in Shortcuts
3. Say Siri phrases → Verify each works
4. Customize intent parameters in Shortcuts
5. Type "note" in Shortcuts → See NoteEntity suggestions
6. Run intent → Verify deep link opens correct screen

**Phase 3 (Interactive):**
1. Tap refresh button in Scratchpad widget → Data refreshes
2. Tap "Open" button → App opens to scratchpad
3. Tap "New Chat" in Quick Actions → Chat created
4. Enable Focus mode → Verify widgets filter content

**Phase 4 (Lock Screen & Polish):**
1. Add circular widget to lock screen → Shows count
2. Search Spotlight for note → Tap result → Opens note
3. Perform action repeatedly → See Siri suggestion appear
4. Wait 15 minutes → Background refresh updates widgets
5. iOS 18: Add Control Center widget → Tap → Opens app

### Regression Testing

**After Each Phase:**
- [ ] Existing widgets still work
- [ ] Deep links still open correct screens
- [ ] Authentication still works across all extensions
- [ ] App still functions normally
- [ ] No performance degradation

---

## Risk Mitigation

### Known Challenges & Solutions

**Challenge:** Widget authentication fails
- **Solution:** Verify keychain access group matches in all entitlements
- **Verification:** Check `KeychainAuthStateStore` initialization in `WidgetEnvironment`

**Challenge:** Widgets show stale data
- **Solution:** Ensure `WidgetDataManager` saves after API calls in main app
- **Verification:** Check `AppEnvironment.updateWidgetData()` is called

**Challenge:** Deep links don't work
- **Solution:** Verify URL scheme in Info.plist and `onOpenURL` handler
- **Verification:** Test `sidebar://chat/123` in Safari

**Challenge:** Siri doesn't recognize phrases
- **Solution:** Ensure `AppShortcutsProvider` is registered and phrases are unique
- **Verification:** Check Shortcuts app shows all intents

**Challenge:** Widget timeline doesn't refresh
- **Solution:** Return correct `Timeline.policy` from provider
- **Verification:** Check 15-minute intervals in logs

---

## Post-Implementation Steps

### 1. Documentation
- Document Siri phrases in README
- Create user guide for widgets setup
- Document Shortcuts workflow examples

### 2. Analytics
- Track widget taps by type
- Track intent usage frequency
- Monitor Siri suggestion acceptance rate

### 3. Optimization
- Monitor widget refresh performance
- Optimize timeline refresh intervals
- Cache more aggressively if needed

### 4. Future Enhancements
- Add more lock screen widget variants
- Create widget for quick note capture with text input (iOS 17+)
- Add StandBy mode optimizations
- Create watch complications (if Watch app exists)

---

## Summary

This comprehensive plan implements Widgets, App Intents, and Siri integration following the proven ShareExtension architecture pattern. Each phase builds incrementally on the previous, allowing for independent shipping and validation.

**Key Success Factors:**
1. Follow existing patterns exactly (ShareExtension as template)
2. Leverage infrastructure already in place (App Groups, Keychain, IPC)
3. Test each phase thoroughly before moving to next
4. Prioritize high-value features first (basic widgets, core intents)
5. Maintain consistent error handling and auth patterns

**Timeline:** 4 weeks, 4 shippable phases
**Risk Level:** Low (using proven patterns)
**User Value:** High (Siri shortcuts, home screen widgets, automation)
