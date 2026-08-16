import Foundation

enum TaskNotificationHandlingResult: Equatable {
    case opened
    case completionQueued
    case completionDeclined
    case ignored
}

@MainActor
struct TaskNotificationResponseHandler {
    let authState: () -> AuthState
    let refresh: ([AnyHashable: Any]) -> Void
    let openRoute: (URL) -> Void
    let completeTask: (String) async -> Bool

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
        case .complete(let taskId):
            let currentAuthState = authState()
            guard currentAuthState == .active || currentAuthState == .staleRecoverable else {
                return .completionDeclined
            }
            return await completeTask(taskId) ? .completionQueued : .completionDeclined
        case .ignore:
            return .ignored
        }
    }
}
