import Foundation

enum TaskNotificationHandlingResult: Equatable {
    case opened
    case completionQueued
    case completionDeclined
    case completionFailed(TaskNotificationCompletionFailure)
    case ignored
}

struct TaskNotificationAuthContext: Equatable {
    let authState: AuthState
    let accountId: String
    let generationId: UUID

    init(
        authState: AuthState,
        accountId: String,
        generationId: UUID = UUID()
    ) {
        self.authState = authState
        self.accountId = accountId
        self.generationId = generationId
    }

    var accountScope: TaskNotificationAccountScope? {
        guard let accountId = UUID(
            uuidString: accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return nil
        }
        return TaskNotificationAccountScope(
            accountId: accountId,
            generationId: generationId
        )
    }
}

@MainActor
struct TaskNotificationResponseHandler {
    let authContext: () -> TaskNotificationAuthContext?
    let refresh: ([AnyHashable: Any]) -> Void
    let openRoute: (URL) -> Void
    let completeTask: (
        String,
        TaskNotificationAccountScope
    ) async -> TaskNotificationCompletionResult

    init(
        authContext: @escaping () -> TaskNotificationAuthContext?,
        refresh: @escaping ([AnyHashable: Any]) -> Void,
        openRoute: @escaping (URL) -> Void,
        completeTask: @escaping (
            String,
            TaskNotificationAccountScope
        ) async -> TaskNotificationCompletionResult
    ) {
        self.authContext = authContext
        self.refresh = refresh
        self.openRoute = openRoute
        self.completeTask = completeTask
    }

    init(
        authContext: @escaping () -> TaskNotificationAuthContext?,
        refresh: @escaping ([AnyHashable: Any]) -> Void,
        openRoute: @escaping (URL) -> Void,
        completeTask: @escaping (String) async -> TaskNotificationCompletionResult
    ) {
        self.init(
            authContext: authContext,
            refresh: refresh,
            openRoute: openRoute,
            completeTask: { taskId, _ in
                await completeTask(taskId)
            }
        )
    }

    func handle(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any],
        completion: () -> Void
    ) async -> TaskNotificationHandlingResult {
        defer { completion() }
        switch TaskNotificationContract.response(
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) {
        case .defaultTap:
            refresh(userInfo)
            if let route = NotificationRoute(userInfo: userInfo) {
                openRoute(route.url)
            }
            return .opened
        case .complete(let taskId, let accountId):
            guard let context = authContext(),
                  context.authState == .active || context.authState == .staleRecoverable,
                  let accountScope = context.accountScope,
                  TaskNotificationContract.accountIdentifier(
                    accountId,
                    matches: context.accountId
                  ) else {
                return .completionDeclined
            }
            switch await completeTask(taskId, accountScope) {
            case .queued:
                return .completionQueued
            case .declined:
                return .completionDeclined
            case .failed(let failure):
                return .completionFailed(failure)
            }
        case .ignore:
            return .ignored
        }
    }
}
