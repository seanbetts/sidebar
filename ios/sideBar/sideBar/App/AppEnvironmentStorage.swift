import Foundation
import sideBarShared

/// Storage dependencies shared by the app environment and its extension handoff paths.
public struct AppEnvironmentStorage {
    public static let shared = AppEnvironmentStorage(
        userDefaults: .standard,
        widgetDataManager: .shared,
        extensionEventStore: .shared,
        pendingShareStore: .shared,
        taskBadgeUpdater: LiveTaskBadgeUpdater()
    )
    public let userDefaults: UserDefaults
    public let widgetDataManager: WidgetDataManager
    public let extensionEventStore: ExtensionEventStore
    public let pendingShareStore: PendingShareStore
    public let taskBadgeUpdater: any TaskBadgeUpdating
    let clearDeliveredActionableTaskNotifications: () -> Void

    public init(
        userDefaults: UserDefaults = .standard,
        widgetDataManager: WidgetDataManager? = nil,
        extensionEventStore: ExtensionEventStore? = nil,
        pendingShareStore: PendingShareStore? = nil,
        taskBadgeUpdater: (any TaskBadgeUpdating)? = nil,
        clearDeliveredActionableTaskNotifications: (() -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.widgetDataManager = widgetDataManager ?? WidgetDataManager(userDefaults: userDefaults)
        self.extensionEventStore = extensionEventStore ?? ExtensionEventStore(userDefaults: userDefaults)
        self.pendingShareStore = pendingShareStore ?? PendingShareStore(userDefaults: userDefaults)
        self.taskBadgeUpdater = taskBadgeUpdater ?? LiveTaskBadgeUpdater()
        self.clearDeliveredActionableTaskNotifications = clearDeliveredActionableTaskNotifications ?? {
            #if os(iOS)
            TaskNotificationContract.clearDeliveredActionableNotifications()
            #endif
        }
    }
}
