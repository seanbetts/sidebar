import Foundation
import UserNotifications

enum TaskNotificationResponse: Equatable {
    case defaultTap
    case complete(taskId: String)
    case ignore
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
              isActionableCategoryIfPresent(userInfo),
              let metadata = userInfo["notification_metadata"] as? [AnyHashable: Any],
              let rawTaskId = metadata["task_id"] as? String else {
            return .ignore
        }
        let taskId = rawTaskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IdentifierValidation.isServerTaskID(taskId) else {
            return .ignore
        }
        return .complete(taskId: taskId)
    }

    private static func isActionableCategoryIfPresent(
        _ userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let aps = userInfo["aps"] as? [AnyHashable: Any],
              let category = aps["category"] as? String else {
            return true
        }
        return category == actionableCategoryIdentifier
    }
}
