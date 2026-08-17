import Foundation
import UserNotifications

enum TaskNotificationResponse: Equatable {
    case defaultTap
    case complete(taskId: String, accountId: String)
    case ignore
}

struct TaskNotificationDelivery: Equatable {
    let requestIdentifier: String
    let categoryIdentifier: String
}

enum TaskNotificationContract {
    static let actionableCategoryIdentifier = "TASK_REMINDER_ACTIONABLE"
    static let summaryCategoryIdentifier = "TASK_REMINDER_SUMMARY"
    static let markCompleteActionIdentifier = "TASK_MARK_COMPLETE"
    static let threadIdentifier = "task-reminders"

    static func categories() -> Set<UNNotificationCategory> {
        let completeAction = UNNotificationAction(
            identifier: markCompleteActionIdentifier,
            title: "Mark Complete",
            options: []
        )
        return [
            UNNotificationCategory(
                identifier: actionableCategoryIdentifier,
                actions: [completeAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: summaryCategoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: []
            )
        ]
    }

    static func response(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> TaskNotificationResponse {
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            return .defaultTap
        }
        guard actionIdentifier == markCompleteActionIdentifier,
              isActionableCategory(userInfo),
              let metadata = userInfo["notification_metadata"] as? [AnyHashable: Any],
              let rawTaskId = metadata["task_id"] as? String,
              let rawAccountId = metadata["account_id"] as? String else {
            return .ignore
        }
        let taskId = rawTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountId = rawAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IdentifierValidation.isServerTaskID(taskId),
              IdentifierValidation.isUUID(accountId) else {
            return .ignore
        }
        return .complete(taskId: taskId, accountId: accountId)
    }

    static func accountIdentifier(
        _ notificationAccountId: String,
        matches currentAccountId: String?
    ) -> Bool {
        guard let currentAccountId,
              let notificationAccountUUID = UUID(
                uuidString: notificationAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              let currentAccountUUID = UUID(
                uuidString: currentAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return false
        }
        return notificationAccountUUID == currentAccountUUID
    }

    static func deliveredActionableRequestIdentifiers(
        in deliveries: [TaskNotificationDelivery]
    ) -> [String] {
        deliveries.compactMap { delivery in
            delivery.categoryIdentifier == actionableCategoryIdentifier
                ? delivery.requestIdentifier
                : nil
        }
    }

    static func clearDeliveredActionableNotifications(
        center: UNUserNotificationCenter = .current()
    ) {
        center.getDeliveredNotifications { notifications in
            let deliveries = notifications.map { notification in
                TaskNotificationDelivery(
                    requestIdentifier: notification.request.identifier,
                    categoryIdentifier: notification.request.content.categoryIdentifier
                )
            }
            let identifiers = deliveredActionableRequestIdentifiers(in: deliveries)
            guard !identifiers.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func isActionableCategory(
        _ userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let aps = userInfo["aps"] as? [AnyHashable: Any],
              let category = aps["category"] as? String else {
            return false
        }
        return category == actionableCategoryIdentifier
    }
}
