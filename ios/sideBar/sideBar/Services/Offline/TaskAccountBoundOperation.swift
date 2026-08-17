import Foundation

struct TaskNotificationAccountScope: Codable, Equatable, Hashable, Sendable {
    let accountId: UUID
    let generationId: UUID
}

public nonisolated final class TaskNotificationAccountScopeCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var storedScope: TaskNotificationAccountScope?

    public init() {}

    var currentScope: TaskNotificationAccountScope? {
        lock.lock()
        defer { lock.unlock() }
        return storedScope
    }

    @discardableResult
    func activate(
        accountId: String,
        generationId: UUID? = nil
    ) -> TaskNotificationAccountScope? {
        guard let accountId = UUID(
            uuidString: accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        if let storedScope, storedScope.accountId == accountId {
            return storedScope
        }
        let scope = TaskNotificationAccountScope(
            accountId: accountId,
            generationId: generationId ?? UUID()
        )
        storedScope = scope
        return scope
    }

    func invalidate() {
        lock.lock()
        storedScope = nil
        lock.unlock()
    }

    func isCurrent(_ scope: TaskNotificationAccountScope) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedScope == scope
    }
}

struct TaskAccountBoundOperationPayload: Codable, Equatable {
    let operation: TaskOperationPayload
    let accountScope: TaskNotificationAccountScope

    private enum CodingKeys: String, CodingKey {
        case operation
        case accountScope = "account_scope"
    }
}
