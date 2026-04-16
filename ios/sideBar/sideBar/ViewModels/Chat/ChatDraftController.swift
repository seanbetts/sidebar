import Foundation

@MainActor
final class ChatDraftController {
    static let entityType = "chat_message_draft"
    static let newChatKey = "new-chat"

    private let draftStorage: DraftStorage?
    private let saveDebounceNanoseconds: UInt64
    private var draftsByKey: [String: String] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]

    private(set) var activeKey: String
    private(set) var currentDraftText: String = ""

    init(
        draftStorage: DraftStorage?,
        initialKey: String = "new-chat",
        saveDebounceNanoseconds: UInt64 = 200_000_000
    ) {
        self.draftStorage = draftStorage
        self.activeKey = initialKey
        self.saveDebounceNanoseconds = saveDebounceNanoseconds
        self.currentDraftText = loadDraft(for: initialKey)
    }

    deinit {
        saveTasks.values.forEach { $0.cancel() }
    }

    static func draftKey(for conversationId: String?) -> String {
        guard let conversationId else {
            return newChatKey
        }
        return "conversation:\(conversationId)"
    }

    func switchContext(to key: String) {
        activeKey = key
        currentDraftText = loadDraft(for: key)
    }

    func updateDraft(_ text: String) {
        currentDraftText = text
        draftsByKey[activeKey] = text
        schedulePersist(text: text, for: activeKey)
    }

    func clearDraft(for key: String) {
        saveTasks[key]?.cancel()
        saveTasks[key] = nil
        draftsByKey.removeValue(forKey: key)
        try? draftStorage?.deleteDraft(entityType: Self.entityType, entityId: key)
        if activeKey == key {
            currentDraftText = ""
        }
    }

    func migrateDraft(from sourceKey: String, to destinationKey: String) {
        guard sourceKey != destinationKey else { return }
        let content = draftsByKey[sourceKey] ?? loadStoredDraft(for: sourceKey) ?? ""
        saveTasks[sourceKey]?.cancel()
        saveTasks[sourceKey] = nil
        draftsByKey.removeValue(forKey: sourceKey)
        try? draftStorage?.deleteDraft(entityType: Self.entityType, entityId: sourceKey)

        activeKey = destinationKey
        currentDraftText = content
        draftsByKey[destinationKey] = content
        schedulePersist(text: content, for: destinationKey)
    }

    private func loadDraft(for key: String) -> String {
        if let cached = draftsByKey[key] {
            return cached
        }
        let stored = loadStoredDraft(for: key) ?? ""
        draftsByKey[key] = stored
        return stored
    }

    private func loadStoredDraft(for key: String) -> String? {
        try? draftStorage?.getDraft(entityType: Self.entityType, entityId: key)?.content
    }

    private func schedulePersist(text: String, for key: String) {
        saveTasks[key]?.cancel()
        saveTasks[key] = Task { [draftStorage, saveDebounceNanoseconds] in
            if saveDebounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: saveDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? draftStorage?.deleteDraft(entityType: Self.entityType, entityId: key)
            } else {
                try? draftStorage?.saveDraft(
                    entityType: Self.entityType,
                    entityId: key,
                    content: text
                )
            }
        }
    }
}
