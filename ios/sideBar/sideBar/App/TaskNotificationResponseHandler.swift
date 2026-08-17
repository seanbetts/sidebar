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
}

@MainActor
struct TaskNotificationResponseHandler {
    let authContext: () -> TaskNotificationAuthContext?
    let refresh: ([AnyHashable: Any]) -> Void
    let openRoute: (URL) -> Void
    let completeTask: (String) async -> TaskNotificationCompletionResult

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
                  TaskNotificationContract.accountIdentifier(
                    accountId,
                    matches: context.accountId
                  ) else {
                return .completionDeclined
            }
            switch await completeTask(taskId) {
            case .queued:
                return .completionQueued
            case .failed(let failure):
                return .completionFailed(failure)
            }
        case .ignore:
            return .ignored
        }
    }
}
