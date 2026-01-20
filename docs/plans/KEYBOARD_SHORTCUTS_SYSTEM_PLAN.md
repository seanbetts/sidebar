# Keyboard Shortcuts System Implementation Plan

## Overview

Implement a comprehensive, context-aware keyboard shortcuts system for the iOS app that enhances productivity, maintains consistency across sections, and provides excellent discoverability for users. This plan covers universal shortcuts, section-specific shortcuts, a centralized registry, and multiple discovery mechanisms.

## Key Principles

- **Context Awareness**: Shortcuts adapt based on current section (Chat, Notes, Websites, Files)
- **Consistency**: Common patterns across sections (⌘N for new, ⌘W for close, ⌘F for search)
- **Discoverability**: Multiple ways for users to learn shortcuts (HUD, reference sheet, inline hints)
- **Platform Native**: Leverage iOS's `UIKeyCommand` with `discoverabilityTitle` for system integration
- **Conflict-Free**: Centralized registry to detect and prevent shortcut conflicts
- **Progressive Enhancement**: Build on existing implementation without breaking current shortcuts

## Current State

### Already Implemented ✅

**File**: `ios/sideBar/sideBar/Views/KeyboardShortcutHandler.swift`

**Existing Shortcuts**:
- `⌘1` → Navigate to Notes
- `⌘2` → Navigate to Tasks
- `⌘3` → Navigate to Websites
- `⌘4` → Navigate to Files
- `⌘5` → Navigate to Chat
- `⌘,` → Open Settings

**Implementation Pattern**:
```swift
final class KeyCommandController: UIViewController {
    override var keyCommands: [UIKeyCommand]? {
        [makeCommand(input: "1", title: "Notes", action: #selector(selectNotes))]
    }
}
```

**Integration**: Embedded in `ContentView.swift:76-82` as zero-sized background view

**Mechanism**: Registry + action router drive `UIKeyCommand` dispatch; `ContentView` responds to shortcut events.

**Implemented System**:
- `KeyboardShortcutRegistry` with conflict logging + context priority
- `ShortcutActionRouter` for context-aware dispatch
- `KeyboardShortcutsView` reference sheet (⌘?)
- Per-section handlers for search focus, list navigation, and dialogs

### Status ✅

- ✅ ⌘N, ⌘W, ⌘F and other universal shortcuts
- ✅ Context-aware shortcuts (chat-specific, notes-specific, etc.)
- ✅ Keyboard shortcuts reference view (⌘?)
- ✅ Centralized shortcut registry
- ✅ Conflict detection system (priority + logging)
- ⏳ Inline shortcut hints in UI (deferred)
- ❌ Command palette (⌘K) - future enhancement

## Complete Shortcut Scheme

### Universal Shortcuts (Work Everywhere)

| Shortcut | Action | Current Status | Priority |
|----------|--------|----------------|----------|
| `⌘1-5` | Navigate to sections | ✅ Implemented | - |
| `⌘,` | Open Settings | ✅ Implemented | - |
| `⌘N` | New item in current section | ✅ Implemented | **P0** |
| `⌘F` | Focus search/filter | ✅ Implemented | **P0** |
| `⌘W` | Close current item | ✅ Implemented | **P0** |
| `⌘R` | Refresh current section | ✅ Implemented | **P1** |
| `⌘?` | Show shortcuts reference | ✅ Implemented | **P0** |
| `⌘⇧P` | Open Scratchpad | ✅ Implemented | **P1** |
| `⌘⇧S` | Toggle sidebar | ✅ Implemented | **P1** |
| `⌘K` | Command palette | ❌ Future | **P3** |

### Chat Section Shortcuts

| Shortcut | Action | Priority |
|----------|--------|----------|
| `⌘N` | New conversation | **P0** |
| `⌘W` | Close current conversation | **P0** |
| `⌘↵` | Send message (when typing) | **P0** |
| `⌘⇧A` | Attach file | **P1** |
| `⌘/` | Stop streaming | **P1** |
| `⌘↑/↓` | Navigate conversations | **P1** |
| `⌘⇧R` | Rename conversation | **P2** |
| `⌘⌫` | Delete conversation | **P2** |

### Notes Section Shortcuts

| Shortcut | Action | Priority |
|----------|--------|----------|
| `⌘N` | Create new note | **P0** |
| `⌘⇧N` | Create new folder | **P1** |
| `⌘W` | Close current note | **P0** |
| `⌘S` | Save note | **P1** |
| `⌘E` | Toggle edit/preview | **P2** |
| `⌘F` | Search notes | **P0** |
| `⌘⇧P` | Pin/Unpin note | **P1** |
| `⌘⇧A` | Archive/Unarchive note | **P1** |
| `⌘⇧R` | Rename note | **P2** |
| `⌘⌫` | Delete note | **P2** |
| `⌘↑/↓` | Navigate notes list | **P1** |
| `⌘B` | Bold (markdown) | **P2** |
| `⌘I` | Italic (markdown) | **P2** |
| `⌘⇧K` | Insert code block | **P2** |

### Websites Section Shortcuts

| Shortcut | Action | Priority |
|----------|--------|----------|
| `⌘N` | Save new website | **P0** |
| `⌘W` | Close current website | **P0** |
| `⌘F` | Search websites | **P0** |
| `⌘⇧P` | Pin/Unpin website | **P1** |
| `⌘⇧A` | Archive/Unarchive | **P1** |
| `⌘⌫` | Delete website | **P2** |
| `⌘↑/↓` | Navigate websites | **P1** |
| `⌘↵` | Open in browser | **P2** |

### Files Section Shortcuts

| Shortcut | Action | Priority |
|----------|--------|----------|
| `⌘N` | Upload new file | **P0** |
| `⌘W` | Close current file | **P0** |
| `⌘F` | Search files | **P0** |
| `⌘⌫` | Delete file | **P2** |
| `⌘↑/↓` | Navigate files | **P1** |
| `⌘⌥O` | Open in default app | **P2** |
| `Space` | Quick Look preview | **P2** |

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                   Keyboard Shortcuts System                      │
├─────────────────────────────────────────────────────────────────┤
│  User Interaction Layer:                                        │
│  • KeyCommandController (UIKit bridge)                          │
│  • Keyboard Shortcuts Reference View                            │
│  • Command Palette (future)                                     │
│  • Inline UI hints                                              │
├─────────────────────────────────────────────────────────────────┤
│  Core Registry:                                                 │
│  • KeyboardShortcutRegistry                                     │
│    - Centralized shortcut definitions                           │
│    - Context filtering                                          │
│    - Conflict detection                                         │
│    - Documentation generation                                   │
├─────────────────────────────────────────────────────────────────┤
│  Action Router:                                                 │
│  • ShortcutActionRouter                                         │
│    - Interprets shortcut actions                                │
│    - Context-aware dispatch                                     │
│    - Calls appropriate ViewModels                               │
├─────────────────────────────────────────────────────────────────┤
│  State Management:                                              │
│  • AppEnvironment.activeContext                                 │
│  • AppEnvironment.commandSelection (existing)                   │
│  • Section-specific ViewModels                                  │
└─────────────────────────────────────────────────────────────────┘
```

### File Structure

```
ios/sideBar/sideBar/
├── Views/
│   ├── KeyboardShortcutHandler.swift (existing - enhance)
│   ├── KeyboardShortcuts/
│   │   ├── KeyboardShortcutsView.swift (NEW)
│   │   ├── ShortcutReferenceSheet.swift (NEW)
│   │   └── CommandPaletteView.swift (NEW - P3)
│   └── ...
├── Models/
│   ├── KeyboardShortcut.swift (NEW)
│   ├── ShortcutContext.swift (NEW)
│   └── ShortcutAction.swift (NEW)
├── Services/
│   ├── KeyboardShortcutRegistry.swift (NEW)
│   └── ShortcutActionRouter.swift (NEW)
└── App/
    └── AppEnvironment.swift (extend)
```

## Data Models

### KeyboardShortcut Model

```swift
public struct KeyboardShortcut: Identifiable, Hashable {
    public let id = UUID()
    public let keys: [String]           // ["cmd", "n"]
    public let input: String            // "n"
    public let modifierFlags: UIKeyModifierFlags
    public let symbol: String           // "⌘N"
    public let title: String            // "New Item"
    public let description: String      // "Create a new item in the current section"
    public let action: ShortcutAction
    public let context: ShortcutContext
    public let isEnabled: Bool          // Future: user can disable

    public init(
        input: String,
        modifiers: UIKeyModifierFlags = .command,
        title: String,
        description: String,
        action: ShortcutAction,
        context: ShortcutContext
    ) {
        self.input = input
        self.modifierFlags = modifiers
        self.title = title
        self.description = description
        self.action = action
        self.context = context
        self.isEnabled = true

        // Generate symbol automatically
        self.symbol = Self.generateSymbol(input: input, modifiers: modifiers)
        self.keys = Self.generateKeys(input: input, modifiers: modifiers)
    }

    private static func generateSymbol(input: String, modifiers: UIKeyModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.alternate) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let key = input.uppercased()
        parts.append(key)
        return parts.joined()
    }

    private static func generateKeys(input: String, modifiers: UIKeyModifierFlags) -> [String] {
        var keys: [String] = []
        if modifiers.contains(.control) { keys.append("ctrl") }
        if modifiers.contains(.alternate) { keys.append("opt") }
        if modifiers.contains(.shift) { keys.append("shift") }
        if modifiers.contains(.command) { keys.append("cmd") }
        keys.append(input)
        return keys
    }
}
```

### ShortcutContext Enum

```swift
public enum ShortcutContext: String, CaseIterable, Identifiable {
    case universal      // Works everywhere
    case chat          // Only in chat section
    case notes         // Only in notes section
    case websites      // Only in websites section
    case files         // Only in files section
    case tasks         // Only in tasks section
    case editing       // When editing content

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .universal: return "Universal"
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .websites: return "Websites"
        case .files: return "Files"
        case .tasks: return "Tasks"
        case .editing: return "Editing"
        }
    }

    public var icon: String {
        switch self {
        case .universal: return "keyboard"
        case .chat: return "bubble"
        case .notes: return "text.document"
        case .websites: return "globe"
        case .files: return "folder"
        case .tasks: return "checkmark.square"
        case .editing: return "pencil"
        }
    }
}
```

### ShortcutAction Enum

```swift
public enum ShortcutAction: Equatable, Hashable {
    // Universal
    case navigateToSection(AppSection)
    case openSettings
    case newItem
    case closeItem
    case search
    case refresh
    case showShortcutsReference
    case toggleSidebar
    case openScratchpad

    // Chat
    case newConversation
    case sendMessage
    case attachFile
    case stopStreaming
    case navigateConversations(direction: NavigationDirection)
    case renameConversation
    case deleteConversation

    // Notes
    case newNote
    case newFolder
    case saveNote
    case toggleEditMode
    case pinNote
    case archiveNote
    case renameNote
    case deleteNote
    case navigateNotes(direction: NavigationDirection)
    case formatBold
    case formatItalic
    case insertCodeBlock

    // Websites
    case newWebsite
    case pinWebsite
    case archiveWebsite
    case deleteWebsite
    case openInBrowser
    case navigateWebsites(direction: NavigationDirection)

    // Files
    case uploadFile
    case deleteFile
    case openInDefaultApp
    case quickLook
    case navigateFiles(direction: NavigationDirection)
}

public enum NavigationDirection {
    case up
    case down
}
```

## Core Services

### KeyboardShortcutRegistry

```swift
@MainActor
public final class KeyboardShortcutRegistry {
    public static let shared = KeyboardShortcutRegistry()

    private init() {}

    // All shortcuts defined in one place
    public let shortcuts: [KeyboardShortcut] = [
        // Universal
        .init(input: "1", title: "Chat", description: "Navigate to Chat section",
              action: .navigateToSection(.chat), context: .universal),
        .init(input: "2", title: "Tasks", description: "Navigate to Tasks section",
              action: .navigateToSection(.tasks), context: .universal),
        .init(input: "3", title: "Websites", description: "Navigate to Websites section",
              action: .navigateToSection(.websites), context: .universal),
        .init(input: "4", title: "Files", description: "Navigate to Files section",
              action: .navigateToSection(.files), context: .universal),
        .init(input: "5", title: "Notes", description: "Navigate to Notes section",
              action: .navigateToSection(.notes), context: .universal),
        .init(input: ",", title: "Settings", description: "Open Settings",
              action: .openSettings, context: .universal),
        .init(input: "n", title: "New Item", description: "Create new item in current section",
              action: .newItem, context: .universal),
        .init(input: "f", title: "Search", description: "Focus search field",
              action: .search, context: .universal),
        .init(input: "w", title: "Close", description: "Close current item",
              action: .closeItem, context: .universal),
        .init(input: "r", title: "Refresh", description: "Refresh current section",
              action: .refresh, context: .universal),
        .init(input: "/", title: "Shortcuts", description: "Show keyboard shortcuts reference",
              action: .showShortcutsReference, context: .universal),
        .init(input: "p", modifiers: [.command, .shift], title: "Scratchpad",
              description: "Open Scratchpad", action: .openScratchpad, context: .universal),

        // Chat-specific
        .init(input: "n", title: "New Chat", description: "Start a new conversation",
              action: .newConversation, context: .chat),
        .init(input: UIKeyCommand.inputReturn, title: "Send", description: "Send message",
              action: .sendMessage, context: .chat),
        .init(input: "a", modifiers: [.command, .shift], title: "Attach File",
              description: "Attach a file to the message", action: .attachFile, context: .chat),
        .init(input: "/", title: "Stop", description: "Stop streaming response",
              action: .stopStreaming, context: .chat),
        .init(input: UIKeyCommand.inputUpArrow, title: "Previous Chat",
              description: "Navigate to previous conversation",
              action: .navigateConversations(direction: .up), context: .chat),
        .init(input: UIKeyCommand.inputDownArrow, title: "Next Chat",
              description: "Navigate to next conversation",
              action: .navigateConversations(direction: .down), context: .chat),

        // Notes-specific
        .init(input: "n", title: "New Note", description: "Create a new note",
              action: .newNote, context: .notes),
        .init(input: "n", modifiers: [.command, .shift], title: "New Folder",
              description: "Create a new folder", action: .newFolder, context: .notes),
        .init(input: "s", title: "Save", description: "Save note",
              action: .saveNote, context: .notes),
        .init(input: "e", title: "Edit Mode", description: "Toggle edit/preview mode",
              action: .toggleEditMode, context: .notes),
        .init(input: "p", modifiers: [.command, .shift], title: "Pin",
              description: "Pin/unpin note", action: .pinNote, context: .notes),
        .init(input: "a", modifiers: [.command, .shift], title: "Archive",
              description: "Archive/unarchive note", action: .archiveNote, context: .notes),
        .init(input: "b", title: "Bold", description: "Bold text",
              action: .formatBold, context: .editing),
        .init(input: "i", title: "Italic", description: "Italic text",
              action: .formatItalic, context: .editing),

        // Websites-specific
        .init(input: "n", title: "New Website", description: "Save a new website",
              action: .newWebsite, context: .websites),
        .init(input: "p", modifiers: [.command, .shift], title: "Pin",
              description: "Pin/unpin website", action: .pinWebsite, context: .websites),
        .init(input: UIKeyCommand.inputReturn, title: "Open", description: "Open in browser",
              action: .openInBrowser, context: .websites),

        // Files-specific
        .init(input: "n", title: "Upload File", description: "Upload a new file",
              action: .uploadFile, context: .files),
        .init(input: " ", modifiers: [], title: "Quick Look", description: "Preview file",
              action: .quickLook, context: .files),
    ]

    // Get shortcuts for specific context
    public func shortcuts(for context: ShortcutContext) -> [KeyboardShortcut] {
        shortcuts.filter { shortcut in
            shortcut.context == context || shortcut.context == .universal
        }
    }

    // Get shortcuts for current app section
    public func shortcuts(for section: AppSection) -> [KeyboardShortcut] {
        let context = contextFor(section: section)
        return shortcuts(for: context)
    }

    // Validate shortcuts for conflicts
    public func validate() -> [ConflictWarning] {
        var conflicts: [ConflictWarning] = []
        var seen: [String: KeyboardShortcut] = [:]

        for shortcut in shortcuts {
            let key = "\(shortcut.context.rawValue):\(shortcut.symbol)"
            if let existing = seen[key] {
                conflicts.append(ConflictWarning(
                    context: shortcut.context,
                    shortcut1: existing,
                    shortcut2: shortcut
                ))
            } else {
                seen[key] = shortcut
            }
        }

        return conflicts
    }

    private func contextFor(section: AppSection) -> ShortcutContext {
        switch section {
        case .chat: return .chat
        case .notes: return .notes
        case .websites: return .websites
        case .files: return .files
        case .tasks: return .tasks
        case .settings: return .universal
        }
    }
}

public struct ConflictWarning {
    let context: ShortcutContext
    let shortcut1: KeyboardShortcut
    let shortcut2: KeyboardShortcut

    var message: String {
        "Conflict in \(context.title): \(shortcut1.symbol) assigned to both '\(shortcut1.title)' and '\(shortcut2.title)'"
    }
}
```

### ShortcutActionRouter

```swift
@MainActor
public final class ShortcutActionRouter {
    private weak var environment: AppEnvironment?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func handle(action: ShortcutAction) {
        guard let env = environment else { return }

        switch action {
        // Universal actions
        case .navigateToSection(let section):
            env.commandSelection = section

        case .openSettings:
            env.commandSelection = .settings

        case .newItem:
            handleNewItem(environment: env)

        case .closeItem:
            handleCloseItem(environment: env)

        case .search:
            handleSearch(environment: env)

        case .refresh:
            handleRefresh(environment: env)

        case .showShortcutsReference:
            // Trigger shortcuts view presentation
            NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)

        case .toggleSidebar:
            // Toggle sidebar via @AppStorage binding
            NotificationCenter.default.post(name: .toggleSidebar, object: nil)

        case .openScratchpad:
            NotificationCenter.default.post(name: .openScratchpad, object: nil)

        // Chat actions
        case .newConversation:
            Task { await env.chatViewModel.startNewConversation() }

        case .sendMessage:
            // Handled by ChatInputBar directly
            break

        case .attachFile:
            NotificationCenter.default.post(name: .attachFile, object: nil)

        case .stopStreaming:
            env.chatViewModel.stopStream()

        case .navigateConversations(let direction):
            handleNavigateConversations(direction: direction, environment: env)

        case .deleteConversation:
            if let id = env.chatViewModel.selectedConversationId {
                Task { await env.chatViewModel.deleteConversation(id: id) }
            }

        // Notes actions
        case .newNote:
            NotificationCenter.default.post(name: .createNewNote, object: nil)

        case .newFolder:
            NotificationCenter.default.post(name: .createNewFolder, object: nil)

        case .saveNote:
            Task { await env.notesEditorViewModel.save() }

        case .pinNote:
            if let id = env.notesViewModel.selectedNoteId {
                let isPinned = env.notesViewModel.noteNode(id: id)?.isPinned ?? false
                Task { await env.notesViewModel.setPinned(id: id, pinned: !isPinned) }
            }

        case .archiveNote:
            if let id = env.notesViewModel.selectedNoteId {
                Task { await env.notesViewModel.setArchived(id: id, archived: true) }
            }

        case .deleteNote:
            if let id = env.notesViewModel.selectedNoteId {
                Task { await env.notesViewModel.deleteNote(id: id) }
            }

        case .formatBold:
            NotificationCenter.default.post(name: .formatBold, object: nil)

        case .formatItalic:
            NotificationCenter.default.post(name: .formatItalic, object: nil)

        // Websites actions
        case .newWebsite:
            NotificationCenter.default.post(name: .saveNewWebsite, object: nil)

        case .deleteWebsite:
            if let id = env.websitesViewModel.selectedWebsiteId {
                Task { await env.websitesViewModel.delete(id: id) }
            }

        // Files actions
        case .uploadFile:
            NotificationCenter.default.post(name: .uploadNewFile, object: nil)

        case .deleteFile:
            if let id = env.ingestionViewModel.selectedFileId {
                Task { await env.ingestionViewModel.delete(fileId: id) }
            }

        default:
            break
        }
    }

    private func handleNewItem(environment: AppEnvironment) {
        // Context-aware: create appropriate item based on active section
        guard let section = currentSection(environment: environment) else { return }

        switch section {
        case .chat:
            Task { await environment.chatViewModel.startNewConversation() }
        case .notes:
            NotificationCenter.default.post(name: .createNewNote, object: nil)
        case .websites:
            NotificationCenter.default.post(name: .saveNewWebsite, object: nil)
        case .files:
            NotificationCenter.default.post(name: .uploadNewFile, object: nil)
        default:
            break
        }
    }

    private func handleCloseItem(environment: AppEnvironment) {
        guard let section = currentSection(environment: environment) else { return }

        switch section {
        case .chat:
            Task { await environment.chatViewModel.closeConversation() }
        case .notes:
            environment.notesViewModel.clearSelection()
        case .websites:
            environment.websitesViewModel.clearSelection()
        case .files:
            environment.ingestionViewModel.clearSelection()
        default:
            break
        }
    }

    private func handleSearch(environment: AppEnvironment) {
        // Post notification to focus search field in current section
        NotificationCenter.default.post(name: .focusSearch, object: nil)
    }

    private func handleRefresh(environment: AppEnvironment) {
        guard let section = currentSection(environment: environment) else { return }

        Task {
            switch section {
            case .chat:
                await environment.chatViewModel.refreshConversations()
            case .notes:
                await environment.notesViewModel.refreshTree(force: true)
            case .websites:
                await environment.websitesViewModel.load()
            case .files:
                await environment.ingestionViewModel.load()
            default:
                break
            }
        }
    }

    private func handleNavigateConversations(direction: NavigationDirection, environment: AppEnvironment) {
        let conversations = environment.chatViewModel.conversations
        guard let currentId = environment.chatViewModel.selectedConversationId,
              let currentIndex = conversations.firstIndex(where: { $0.id == currentId }) else {
            return
        }

        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(0, currentIndex - 1)
        case .down:
            nextIndex = min(conversations.count - 1, currentIndex + 1)
        }

        if nextIndex != currentIndex {
            Task { await environment.chatViewModel.selectConversation(id: conversations[nextIndex].id) }
        }
    }

    private func currentSection(environment: AppEnvironment) -> AppSection? {
        // Determine from UI state - could be tracked in AppEnvironment
        // For now, infer from selected IDs
        if environment.chatViewModel.selectedConversationId != nil {
            return .chat
        } else if environment.notesViewModel.selectedNoteId != nil {
            return .notes
        } else if environment.websitesViewModel.selectedWebsiteId != nil {
            return .websites
        } else if environment.ingestionViewModel.selectedFileId != nil {
            return .files
        }
        return nil
    }
}

// Notification names
extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let openScratchpad = Notification.Name("openScratchpad")
    static let attachFile = Notification.Name("attachFile")
    static let createNewNote = Notification.Name("createNewNote")
    static let createNewFolder = Notification.Name("createNewFolder")
    static let formatBold = Notification.Name("formatBold")
    static let formatItalic = Notification.Name("formatItalic")
    static let saveNewWebsite = Notification.Name("saveNewWebsite")
    static let uploadNewFile = Notification.Name("uploadNewFile")
    static let focusSearch = Notification.Name("focusSearch")
}
```

## Enhanced KeyboardShortcutHandler

Update the existing file to use the registry:

```swift
// ios/sideBar/sideBar/Views/KeyboardShortcutHandler.swift

import SwiftUI
import UIKit

struct KeyboardShortcutHandler: UIViewControllerRepresentable {
    @EnvironmentObject var environment: AppEnvironment

    func makeUIViewController(context: Context) -> KeyCommandController {
        let controller = KeyCommandController()
        controller.environment = environment
        controller.actionRouter = ShortcutActionRouter(environment: environment)
        return controller
    }

    func updateUIViewController(_ uiViewController: KeyCommandController, context: Context) {
        uiViewController.environment = environment
    }
}

final class KeyCommandController: UIViewController {
    var environment: AppEnvironment?
    var actionRouter: ShortcutActionRouter?
    private let registry = KeyboardShortcutRegistry.shared

    override var keyCommands: [UIKeyCommand]? {
        guard let environment else { return [] }

        let universalShortcuts = registry.shortcuts(for: .universal)
        let contextShortcuts = contextualShortcuts()

        let allShortcuts = universalShortcuts + contextShortcuts

        return allShortcuts.map { shortcut in
            let command = UIKeyCommand(
                input: shortcut.input,
                modifierFlags: shortcut.modifierFlags,
                action: #selector(handleShortcut(_:))
            )
            command.discoverabilityTitle = shortcut.title
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    private func contextualShortcuts() -> [KeyboardShortcut] {
        guard let environment else { return [] }

        // Determine current context based on active section
        let section = inferActiveSection()
        guard let section else { return [] }

        return registry.shortcuts(for: section)
    }

    private func inferActiveSection() -> AppSection? {
        guard let env = environment else { return nil }

        if env.chatViewModel.selectedConversationId != nil {
            return .chat
        } else if env.notesViewModel.selectedNoteId != nil {
            return .notes
        } else if env.websitesViewModel.selectedWebsiteId != nil {
            return .websites
        } else if env.ingestionViewModel.selectedFileId != nil {
            return .files
        }

        return nil
    }

    @objc private func handleShortcut(_ command: UIKeyCommand) {
        guard let environment, let actionRouter else { return }

        // Find the shortcut matching this command
        let allShortcuts = registry.shortcuts
        guard let shortcut = allShortcuts.first(where: {
            $0.input == command.input && $0.modifierFlags == command.modifierFlags
        }) else {
            return
        }

        // Route the action
        actionRouter.handle(action: shortcut.action)
    }
}
```

## Keyboard Shortcuts Reference View

```swift
// ios/sideBar/sideBar/Views/KeyboardShortcuts/KeyboardShortcutsView.swift

import SwiftUI

public struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var selectedContext: ShortcutContext? = nil

    private let registry = KeyboardShortcutRegistry.shared

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                Divider()
                contextPicker
                Divider()
                shortcutsList
            }
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search shortcuts", text: $searchQuery)
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var contextPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ContextChip(
                    title: "All",
                    icon: "keyboard",
                    isSelected: selectedContext == nil
                ) {
                    selectedContext = nil
                }

                ForEach(ShortcutContext.allCases) { context in
                    ContextChip(
                        title: context.title,
                        icon: context.icon,
                        isSelected: selectedContext == context
                    ) {
                        selectedContext = context
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private var shortcutsList: some View {
        List {
            ForEach(groupedShortcuts(), id: \.context) { group in
                Section {
                    ForEach(group.shortcuts) { shortcut in
                        ShortcutRow(shortcut: shortcut)
                    }
                } header: {
                    HStack {
                        Image(systemName: group.context.icon)
                        Text(group.context.title)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func groupedShortcuts() -> [ShortcutGroup] {
        let allShortcuts = registry.shortcuts

        // Filter by search
        let filtered = searchQuery.isEmpty ? allShortcuts : allShortcuts.filter { shortcut in
            shortcut.title.localizedCaseInsensitiveContains(searchQuery) ||
            shortcut.description.localizedCaseInsensitiveContains(searchQuery) ||
            shortcut.symbol.localizedCaseInsensitiveContains(searchQuery)
        }

        // Filter by context
        let contextFiltered = selectedContext == nil ? filtered : filtered.filter { shortcut in
            shortcut.context == selectedContext || shortcut.context == .universal
        }

        // Group by context
        let grouped = Dictionary(grouping: contextFiltered) { $0.context }

        return grouped.map { context, shortcuts in
            ShortcutGroup(context: context, shortcuts: shortcuts)
        }.sorted { $0.context.rawValue < $1.context.rawValue }
    }
}

private struct ShortcutGroup {
    let context: ShortcutContext
    let shortcuts: [KeyboardShortcut]
}

private struct ContextChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: KeyboardShortcut

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut.title)
                    .font(.body)
                Text(shortcut.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(shortcut.symbol)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}
```

## Implementation Plan

### Phase 1: Core Infrastructure (Week 1) - **P0**

**Goals**: Set up foundation, enhance existing handler, add universal shortcuts

**Files to Create**:
- `Models/KeyboardShortcut.swift`
- `Models/ShortcutContext.swift`
- `Models/ShortcutAction.swift`
- `Services/KeyboardShortcutRegistry.swift`
- `Services/ShortcutActionRouter.swift`

**Files to Modify**:
- `Views/KeyboardShortcutHandler.swift` (enhance)
- `App/AppEnvironment.swift` (add actionRouter property)

**Tasks**:
1. Create data models (ShortcutContext, ShortcutAction, KeyboardShortcut)
2. Build KeyboardShortcutRegistry with all shortcuts defined
3. Implement ShortcutActionRouter with universal actions
4. Enhance KeyboardShortcutHandler to use registry
5. Add NotificationCenter patterns for UI events
6. Wire up AppEnvironment with action router
7. Test universal shortcuts:
   - ⌘N (new item)
   - ⌘W (close item)
   - ⌘F (search)
   - ⌘R (refresh)

**Success Criteria**:
- All universal shortcuts working
- No regressions on existing ⌘1-5 shortcuts
- Clean separation between registry, router, and handler
- Conflict detection reports no issues

### Phase 2: Shortcuts Reference View (Week 1-2) - **P0**

**Goals**: Make shortcuts discoverable via reference sheet

**Files to Create**:
- `Views/KeyboardShortcuts/KeyboardShortcutsView.swift`
- `Views/KeyboardShortcuts/ShortcutReferenceSheet.swift`

**Files to Modify**:
- `Views/ContentView.swift` (add sheet presentation)
- `Views/SiteHeaderBar.swift` (add help button)

**Tasks**:
1. Build KeyboardShortcutsView with search and filtering
2. Add ⌘/ shortcut to show reference
3. Add "Keyboard Shortcuts" option in Settings
4. Add help button in header (optional)
5. Style reference view to match app design
6. Test search and filtering

**Success Criteria**:
- ⌘/ opens shortcuts reference
- All shortcuts visible and searchable
- Context filtering works correctly
- Reference can be dismissed with Escape or Done button

### Phase 3: Section-Specific Shortcuts (Week 2) - **P1**

**Goals**: Implement context-aware shortcuts for each section

**Files to Modify**:
- `Services/ShortcutActionRouter.swift` (add section actions)
- `Views/KeyboardShortcutHandler.swift` (context detection)
- Section-specific views (for notification handling)

**Tasks**:
1. **Chat shortcuts**:
   - ⌘N (new conversation)
   - ⌘⇧A (attach file)
   - ⌘/ (stop streaming)
   - ⌘↑/↓ (navigate conversations)

2. **Notes shortcuts**:
   - ⌘N (new note)
   - ⌘⇧N (new folder)
   - ⌘⇧P (pin/unpin)
   - ⌘⇧A (archive)
   - ⌘↑/↓ (navigate notes)

3. **Websites shortcuts**:
   - ⌘N (save website)
   - ⌘⇧P (pin/unpin)
   - ⌘↵ (open in browser)

4. **Files shortcuts**:
   - ⌘N (upload file)
   - ⌘↑/↓ (navigate files)

5. Update KeyboardShortcutHandler to return context-specific commands

**Success Criteria**:
- Section-specific shortcuts work in appropriate contexts
- No conflicts between contexts
- Shortcuts update when switching sections
- discoverabilityTitle shows correct shortcuts per section

### Phase 4: Inline Hints & Polish (Week 3) - **P1**

**Goals**: Surface shortcuts in UI, add first-run tips

**Files to Modify**:
- Various view files (add .help() modifiers)
- Empty state views (add shortcut hints)
- Button labels (add keyboard shortcut display)

**Tasks**:
1. Add .help() tooltips to buttons with shortcuts
2. Update empty states to mention shortcuts
3. Add first-run tip banner (⌘/ to see shortcuts)
4. Store tip dismissal in @AppStorage
5. Add shortcut symbols to context menus where appropriate
6. Polish shortcut reference view design

**Success Criteria**:
- Shortcuts visible in tooltips on hover
- Empty states mention relevant shortcuts
- First-run tip shows once and is dismissible
- Context menus show shortcut symbols

### Phase 5: Advanced Features (Week 4+) - **P2-P3**

**Goals**: Markdown formatting, destructive actions, command palette (future)

**Files to Create**:
- `Views/KeyboardShortcuts/CommandPaletteView.swift` (future)

**Tasks**:
1. **Markdown formatting shortcuts**:
   - ⌘B (bold)
   - ⌘I (italic)
   - ⌘⇧K (code block)
   - Integrate with MarkdownEditorView

2. **Destructive action shortcuts**:
   - ⌘⌫ (delete with confirmation)
   - Add confirmation alerts

3. **Additional polish**:
   - ⌘⇧S (toggle sidebar)
   - ⌘⇧P (scratchpad)
   - Space (Quick Look)

4. **Command Palette** (P3 - Future):
   - ⌘K to open
   - Fuzzy search all actions
   - Show shortcuts next to actions
   - Integrate with existing actions

**Success Criteria**:
- Markdown shortcuts work in editor
- Destructive actions require confirmation
- All polish shortcuts functional
- Command palette design spec ready (not implemented)

## Testing Strategy

### Unit Tests
- KeyboardShortcutRegistry conflict detection
- ShortcutActionRouter action routing
- Context inference logic

### Integration Tests
- Shortcut invocation → Action execution
- Context switching → Command updates
- Search filtering in reference view

### Manual Testing Checklist
- [ ] All universal shortcuts work in every section
- [ ] Section shortcuts only work in appropriate sections
- [ ] ⌘/ opens reference view from anywhere
- [ ] Reference view search works correctly
- [ ] Context filtering in reference view works
- [ ] No shortcut conflicts detected
- [ ] Existing ⌘1-5 shortcuts still work
- [ ] discoverabilityTitle shows in iOS HUD (long-press Cmd)
- [ ] Shortcuts work on iPad with keyboard
- [ ] Tooltips show on hover (iPad with trackpad)
- [ ] First-run tip appears once
- [ ] Settings has keyboard shortcuts link

### Regression Testing
- Ensure existing shortcuts (⌘1-5, ⌘,) continue working
- Verify no impact on text input in chat/notes
- Check that shortcuts don't interfere with system shortcuts
- Verify iPad split-view keyboard handling

## Success Metrics

### Discoverability
- 80% of users who connect a keyboard discover at least one shortcut within first session
- ⌘/ reference view accessed by 50% of keyboard users within first week

### Adoption
- Track usage of top 5 shortcuts via analytics (optional)
- Measure reduction in mouse/touch interactions for common actions

### Quality
- Zero reported conflicts between shortcuts
- <5 bug reports related to shortcuts in first month
- Positive user feedback on discoverability

## Future Enhancements

### User Customization (Post-MVP)
- Allow users to customize shortcuts
- Conflict detection for custom shortcuts
- Import/export shortcut configs
- Reset to defaults option

### Command Palette (P3)
- ⌘K to open palette
- Fuzzy search all actions
- Recent actions list
- Quick switcher for sections/items

### Additional Shortcuts
- Multi-selection with Shift
- Select all (⌘A) in lists
- Copy/paste for items
- Undo/redo for text editing

### macOS Parity
- Ensure keyboard shortcuts work on macOS build
- Use native SwiftUI .keyboardShortcut() where possible
- CommandMenu integration for macOS menu bar

## Migration Notes

### Breaking Changes
- None. This is purely additive functionality.

### Backward Compatibility
- All existing shortcuts (⌘1-5, ⌘,) preserved
- Existing KeyCommandController flow maintained
- No changes to public APIs

### Rollout Strategy
1. Phase 1: Deploy universal shortcuts to beta testers
2. Phase 2: Add reference view, collect feedback
3. Phase 3: Roll out section-specific shortcuts incrementally
4. Phase 4: Polish and optimize based on usage data

## Documentation

### User-Facing
- Add "Keyboard Shortcuts" section to in-app help
- Update App Store description to mention keyboard support
- Create blog post announcing keyboard shortcuts

### Developer-Facing
- Document KeyboardShortcutRegistry usage
- Document how to add new shortcuts
- Document ShortcutActionRouter patterns
- Add code comments for context detection logic

## Open Questions

1. **Should shortcuts be customizable in v1?**
   - Decision: No, keep it simple. Add in future version if requested.

2. **How to handle conflicts between app and system shortcuts?**
   - Decision: Use `wantsPriorityOverSystemBehavior` flag judiciously. Avoid overriding essential system shortcuts.

3. **Should we track shortcut usage analytics?**
   - Decision: Optional. Add if privacy-compliant analytics already exist.

4. **How to handle shortcuts in modal views?**
   - Decision: Modal views can have their own KeyCommandController if needed. Start simple.

5. **Should Command Palette be in v1?**
   - Decision: No. Phase 5 (P3). Get basic shortcuts right first.

## Summary

This plan establishes a comprehensive, maintainable keyboard shortcuts system for the iOS app that:
- Builds on existing implementation without breaking changes
- Provides universal and context-aware shortcuts
- Includes excellent discoverability mechanisms
- Uses centralized registry for maintainability
- Follows platform conventions
- Leaves room for future enhancements

The phased approach allows for incremental delivery and testing, with core functionality (universal shortcuts + reference view) delivered in Weeks 1-2, and polish/advanced features in Weeks 3-4+.
