import Foundation
import sideBarShared

/// Defines ChatStreamEventType.
public enum ChatStreamEventType: String {
    case token
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case complete
    case error
    case collectionInvalidated = "collection_invalidated"
    case entityChanged = "entity_changed"
    case entityDeleted = "entity_deleted"
    case promptPreview = "prompt_preview"
    case toolConfirmationRequested = "tool_confirmation_requested"
    case toolConfirmationResolved = "tool_confirmation_resolved"
    case toolStatus = "tool_status"
    case undoAvailable = "undo_available"
    case workspacePatch = "workspace_patch"
}

public extension ChatStreamEventType {
    static let noteCreated: Self = .entityChanged
    static let noteUpdated: Self = .entityChanged
    static let notePinned: Self = .entityChanged
    static let noteMoved: Self = .entityChanged
    static let noteDeleted: Self = .entityDeleted
    static let conversationTitleUpdated: Self = .entityChanged
    static let websiteSaved: Self = .entityChanged
    static let websiteRenamed: Self = .entityChanged
    static let websitePinned: Self = .entityChanged
    static let websiteArchived: Self = .entityChanged
    static let websiteDeleted: Self = .entityDeleted
    static let ingestionUpdated: Self = .collectionInvalidated
    static let themeSet: Self = .collectionInvalidated
    static let scratchpadUpdated: Self = .collectionInvalidated
    static let scratchpadCleared: Self = .collectionInvalidated
    static let toolStart: Self = .toolStatus
    static let toolEnd: Self = .toolStatus
    static let memoryCreated: Self = .collectionInvalidated
    static let memoryUpdated: Self = .collectionInvalidated
    static let memoryDeleted: Self = .collectionInvalidated
    static let assistantIdentityUpdated: Self = .collectionInvalidated
    static let assistantSoulUpdated: Self = .collectionInvalidated
    static let profileUserSettingsUpdated: Self = .collectionInvalidated
    static let otherPreferencesUpdated: Self = .collectionInvalidated
    static let onboardingProviderBlocked: Self = .collectionInvalidated
    static let onboardingResumeSuggested: Self = .collectionInvalidated
    static let onboardingMilestoneCompleted: Self = .collectionInvalidated
}

/// Declares supported sync entity types.
public enum ChatStreamEntityType: String, CaseIterable {
    case assistantSettings = "assistant_settings"
    case conversation
    case ingestion
    case memory
    case note
    case onboardingState = "onboarding_state"
    case preferences
    case profile
    case scratchpad
    case tasks
    case website
    case workspace
}

/// Declares supported entity change types.
public enum ChatStreamChangeType: String, CaseIterable {
    case archived
    case cleared
    case completed
    case created
    case deleted
    case moved
    case opened
    case pinned
    case renamed
    case unarchived
    case unpinned
    case updated
}

/// Declares client-side sync handling policy for an entity type.
public enum ChatStreamEntitySyncPolicy: String {
    case patchThenInvalidate
    case invalidateFirst
    case specialCase
}

public let chatStreamCustomEventNames: [String] = [
    "collection_invalidated",
    "entity_changed",
    "entity_deleted",
    "prompt_preview",
    "tool_confirmation_requested",
    "tool_confirmation_resolved",
    "tool_status",
    "undo_available",
    "workspace_patch"
]

public let chatStreamEventTypeByName: [String: ChatStreamEventType] = [
    "complete": .complete,
    "collection_invalidated": .collectionInvalidated,
    "entity_changed": .entityChanged,
    "entity_deleted": .entityDeleted,
    "error": .error,
    "prompt_preview": .promptPreview,
    "token": .token,
    "tool_call": .toolCall,
    "tool_confirmation_requested": .toolConfirmationRequested,
    "tool_confirmation_resolved": .toolConfirmationResolved,
    "tool_result": .toolResult,
    "tool_status": .toolStatus,
    "undo_available": .undoAvailable,
    "workspace_patch": .workspacePatch
]

public let chatStreamEntityTypeNames: [String] = [
    "assistant_settings",
    "conversation",
    "ingestion",
    "memory",
    "note",
    "onboarding_state",
    "preferences",
    "profile",
    "scratchpad",
    "tasks",
    "website",
    "workspace"
]

public let chatStreamChangeTypeNames: [String] = [
    "archived",
    "cleared",
    "completed",
    "created",
    "deleted",
    "moved",
    "pinned",
    "renamed",
    "unarchived",
    "unpinned",
    "updated"
]

public let chatStreamEntitySyncPolicies: [ChatStreamEntityType: ChatStreamEntitySyncPolicy] = [
    .assistantSettings: .invalidateFirst,
    .conversation: .patchThenInvalidate,
    .ingestion: .invalidateFirst,
    .memory: .invalidateFirst,
    .note: .patchThenInvalidate,
    .onboardingState: .invalidateFirst,
    .preferences: .invalidateFirst,
    .profile: .invalidateFirst,
    .scratchpad: .invalidateFirst,
    .tasks: .invalidateFirst,
    .website: .patchThenInvalidate,
    .workspace: .specialCase
]

/// Represents ChatStreamEvent.
public struct ChatStreamEvent {
    public let type: ChatStreamEventType
    public let data: AnyCodable?

    public init(type: ChatStreamEventType, data: AnyCodable?) {
        self.type = type
        self.data = data
    }
}
