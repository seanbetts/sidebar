#if os(iOS)
import OSLog
import UIKit
import UserNotifications

extension AppLaunchDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        _ = center
        AppEnvironment.shared?.handleRemoteNotification(notification.request.content.userInfo)
        completionHandler([.badge, .banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = center
        let userInfo = response.notification.request.content.userInfo
        let handler = TaskNotificationResponseHandler(
            authContext: {
                AppEnvironment.shared?.taskNotificationAuthContext
            },
            refresh: { payload in
                AppEnvironment.shared?.handleRemoteNotification(payload)
            },
            openRoute: { route in
                AppEnvironment.shared?.handleDeepLink(route)
            },
            completeTask: { taskId, accountScope in
                guard let environment = AppEnvironment.shared else {
                    return .failed(.unavailable)
                }
                return await environment.tasksViewModel
                    .completeDueTodayTaskFromNotification(
                        taskId: taskId,
                        accountScope: accountScope
                    )
            }
        )
        Task { @MainActor in
            let result = await handler.handle(
                actionIdentifier: response.actionIdentifier,
                userInfo: userInfo,
                completion: completionHandler
            )
            Self.logTaskNotificationHandlingResult(result)
        }
    }

    private static func logTaskNotificationHandlingResult(
        _ result: TaskNotificationHandlingResult
    ) {
        let logger = Logger(subsystem: "sideBar", category: "Push")
        switch result {
        case .completionDeclined:
            logger.info("Task notification completion was not queued.")
        case .completionFailed(.queueFull):
            logger.info("Task notification completion queue is full.")
        case .completionFailed(.unavailable):
            logger.error("Task notification completion queue is unavailable.")
        default:
            break
        }
    }
}
#endif
