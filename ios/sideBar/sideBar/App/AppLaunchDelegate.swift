import BackgroundTasks
import sideBarShared
import Foundation
import os
import UserNotifications

final class BackgroundProcessingTaskExpirationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didExpire = false

    func markExpired(canceling task: Task<Bool, Never>) {
        lock.lock()
        didExpire = true
        lock.unlock()
        task.cancel()
    }

    func completedSuccessfully(workSucceeded: Bool) -> Bool {
        lock.lock()
        let expired = didExpire
        lock.unlock()
        return workSucceeded && !expired
    }
}

#if os(iOS)
import UIKit

// MARK: - AppLaunchDelegate

final class AppLaunchDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let tokenRefreshTaskIdentifier = "ai.sidebar.sidebar.tokenrefresh"
    static let widgetRefreshTaskIdentifier = "ai.sidebar.sidebar.widgetrefresh"
    static let websiteSaveContinuationTaskIdentifier = "ai.sidebar.sidebar.website-save"
    static let writeQueueFlushTaskIdentifier = "ai.sidebar.sidebar.writequeue"
    enum ShortcutCommandKeys {
        static let type = "type"
        static let section = "section"
        static let direction = "direction"
        static let commandId = "command_id"
    }

    enum ShortcutCommandType: String {
        case navigate
        case openSettings
        case newItem
        case closeItem
        case focusSearch
        case refreshSection
        case showShortcuts
        case openScratchpad
        case toggleSidebar
        case sendMessage
        case attachFile
        case completeTask
        case editTaskNotes
        case moveTask
        case setTaskDueDate
        case setTaskRepeat
        case renameItem
        case deleteItem
        case pinItem
        case archiveItem
        case openInBrowser
        case createFolder
        case navigateList
        case openInDefaultApp
        case quickLook
    }

    private let shortcutsFileIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.file")
    private let shortcutsEditIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.edit")
    private let shortcutsViewIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.view")
    private let shortcutsWindowIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.window")
    private let shortcutsHelpIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.help")
    private let shortcutsContextIdentifier = UIMenu.Identifier("ai.sidebar.shortcuts.context")
    private let router = ShortcutActionRouter()
    private let logger = Logger(subsystem: "sideBar", category: "Push")

    override init() {
        super.init()
        #if DEBUG
        AppLaunchMetrics.shared.mark("AppLaunchDelegate init")
        #endif
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppLaunchMetrics.shared.mark("willFinishLaunching")
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.setNotificationCategories(TaskNotificationContract.categories())
        if let config = try? EnvironmentConfig.load() {
            SentryBootstrap.startIfConfigured(config: config)
        }
        #if DEBUG
        AppLaunchMetrics.shared.mark("didFinishLaunching")
        assertBackgroundTaskIdentifiersConfigured()
        #endif

        // Register background task for token refresh
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.tokenRefreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handleTokenRefresh(task: refreshTask)
        }

        // Register background task for widget data refresh
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.widgetRefreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handleWidgetRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.websiteSaveContinuationTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self?.handleWebsiteSaveContinuation(task: processingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.writeQueueFlushTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self?.handleWriteQueueFlush(task: processingTask)
        }

        return true
    }

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
            authState: {
                AppEnvironment.shared?.authState ?? .signedOut
            },
            refresh: { payload in
                AppEnvironment.shared?.handleRemoteNotification(payload)
            },
            openRoute: { route in
                AppEnvironment.shared?.handleDeepLink(route)
            },
            completeTask: { taskId in
                guard let environment = AppEnvironment.shared else { return false }
                return await environment.tasksViewModel.completeTask(taskId: taskId)
            }
        )
        Task { @MainActor [weak self] in
            let result = await handler.handle(
                actionIdentifier: response.actionIdentifier,
                userInfo: userInfo,
                completion: completionHandler
            )
            if result == .completionDeclined {
                self?.logger.info("Task notification completion was not queued.")
            }
        }
    }

    // MARK: - Background Token Refresh

    private func handleTokenRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh
        Self.scheduleTokenRefresh()

        let refreshTask = Task {
            guard let environment = AppEnvironment.shared,
                  environment.authState == .active else {
                return false
            }
            await environment.container.authSession.refreshSession()
            return true
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            let success = await refreshTask.value
            task.setTaskCompleted(success: success)
        }
    }

    static func scheduleTokenRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: tokenRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let logger = Logger(subsystem: "sideBar", category: "BackgroundTask")
            logger.error("Failed to schedule token refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Background Widget Refresh

    private func handleWidgetRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh
        Self.scheduleWidgetRefresh()

        let widgetTask = Task {
            guard let environment = AppEnvironment.shared,
                  environment.authState == .active else {
                return false
            }
            // Apply widget task completions and refresh counts so badge stays in sync.
            await environment.consumeWidgetCompletions()
            await environment.tasksViewModel.loadCounts(force: true)
            // Refresh all widget data in parallel
            async let tasks: () = environment.tasksViewModel.refreshWidgetData()
            async let notes: () = environment.notesRuntime.viewModel.refreshWidgetData()
            async let websites: () = environment.websitesViewModel.refreshWidgetData()
            async let files: () = environment.ingestionViewModel.refreshWidgetData()
            _ = await (tasks, notes, websites, files)
            return true
        }

        task.expirationHandler = {
            widgetTask.cancel()
        }

        Task {
            let success = await widgetTask.value
            task.setTaskCompleted(success: success)
        }
    }

    static func scheduleWidgetRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: widgetRefreshTaskIdentifier)
        // Schedule for 30 minutes - iOS may defer based on system conditions
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let logger = Logger(subsystem: "sideBar", category: "BackgroundTask")
            logger.error("Failed to schedule widget refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Background Website Save Continuation

    private func handleWebsiteSaveContinuation(task: BGProcessingTask) {
        let continuationTask = Task {
            guard let environment = AppEnvironment.shared else {
                return false
            }
            return await environment.performBackgroundWebsiteContinuation()
        }
        let expirationState = BackgroundProcessingTaskExpirationState()

        task.expirationHandler = {
            expirationState.markExpired(canceling: continuationTask)
        }

        Task {
            let success = await continuationTask.value
            if let environment = AppEnvironment.shared,
               environment.hasPendingWebsiteBackgroundWork {
                Self.scheduleWebsiteSaveContinuation()
            }
            task.setTaskCompleted(success: expirationState.completedSuccessfully(workSucceeded: success))
        }
    }

    static func scheduleWebsiteSaveContinuation() {
        let request = BGProcessingTaskRequest(identifier: websiteSaveContinuationTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let logger = Logger(subsystem: "sideBar", category: "BackgroundTask")
            logger.error(
                "Failed to schedule website save continuation: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Background Write Queue Flush

    private func handleWriteQueueFlush(task: BGProcessingTask) {
        let flushTask = Task {
            guard let environment = AppEnvironment.shared else {
                return false
            }
            return await environment.performBackgroundWriteQueueFlush()
        }
        let expirationState = BackgroundProcessingTaskExpirationState()

        task.expirationHandler = {
            expirationState.markExpired(canceling: flushTask)
        }

        Task {
            let success = await flushTask.value
            if let environment = AppEnvironment.shared,
               await environment.writeQueue.hasPendingWritesNeedingFlush() {
                Self.scheduleWriteQueueFlush()
            }
            task.setTaskCompleted(success: expirationState.completedSuccessfully(workSucceeded: success))
        }
    }

    static func scheduleWriteQueueFlush() {
        let request = BGProcessingTaskRequest(identifier: writeQueueFlushTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let logger = Logger(subsystem: "sideBar", category: "BackgroundTask")
            logger.error("Failed to schedule write queue flush: \(error.localizedDescription, privacy: .public)")
        }
    }

#if DEBUG
    private func assertBackgroundTaskIdentifiersConfigured() {
        let key = "BGTaskSchedulerPermittedIdentifiers"
        guard let configured = Bundle.main.object(forInfoDictionaryKey: key) as? [String] else {
            assertionFailure("Missing \(key) in app Info.plist")
            return
        }
        let expected = [
            Self.tokenRefreshTaskIdentifier,
            Self.widgetRefreshTaskIdentifier,
            Self.websiteSaveContinuationTaskIdentifier,
            Self.writeQueueFlushTaskIdentifier
        ]
        let missing = expected.filter { configured.contains($0) == false }
        if missing.isEmpty == false {
            assertionFailure("Missing BG task identifiers in Info.plist: \(missing.joined(separator: ", "))")
        }
    }
#endif

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = AppSceneDelegate.self
        return configuration
    }

    // URL handling moved to UIWindowSceneDelegate to avoid deprecated API.

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard !tokenString.isEmpty else { return }
        AppEnvironment.shared?.updateDeviceToken(tokenString)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Remote notifications registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let environment = AppEnvironment.shared else {
            completionHandler(.noData)
            return
        }
        environment.handleRemoteNotification(userInfo)
        completionHandler(.newData)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }

        builder.remove(menu: shortcutsFileIdentifier)
        builder.remove(menu: shortcutsEditIdentifier)
        builder.remove(menu: shortcutsViewIdentifier)
        builder.remove(menu: shortcutsWindowIdentifier)
        builder.remove(menu: shortcutsHelpIdentifier)
        builder.remove(menu: shortcutsContextIdentifier)

        let shortcuts = currentShortcuts()
        let universalShortcuts = shortcuts.filter { $0.contexts.contains(.universal) }
        let sectionShortcuts = shortcuts.filter { !$0.contexts.contains(.universal) }

        let categorized = categorizeShortcuts(
            universal: universalShortcuts,
            contextual: sectionShortcuts
        )

        if let fileMenu = makeMenu(identifier: shortcutsFileIdentifier, shortcuts: categorized.file) {
            builder.insertChild(fileMenu, atEndOfMenu: .file)
        }
        if let editMenu = makeMenu(identifier: shortcutsEditIdentifier, shortcuts: categorized.edit) {
            builder.insertChild(editMenu, atEndOfMenu: .edit)
        }
        if let viewMenu = makeMenu(identifier: shortcutsViewIdentifier, shortcuts: categorized.view) {
            builder.insertChild(viewMenu, atEndOfMenu: .view)
        }
        if let windowMenu = makeMenu(identifier: shortcutsWindowIdentifier, shortcuts: categorized.window) {
            if builder.menu(for: .window) != nil {
                builder.insertChild(windowMenu, atEndOfMenu: .window)
            } else {
                builder.insertChild(windowMenu, atEndOfMenu: .file)
            }
        }
        if let helpMenu = makeMenu(identifier: shortcutsHelpIdentifier, shortcuts: categorized.help) {
            builder.insertChild(helpMenu, atEndOfMenu: .help)
        }
    }

    @objc
    private func handleShortcut(_ sender: UIKeyCommand) {
        guard let payload = sender.propertyList as? [String: String],
              let action = shortcutAction(from: payload),
              let environment = AppEnvironment.shared else { return }
        Task { @MainActor in
            router.handle(action, environment: environment)
        }
    }

    private func currentContexts() -> Set<ShortcutContext> {
        AppEnvironment.shared?.activeShortcutContexts ?? [.universal]
    }

    private func currentShortcuts() -> [KeyboardShortcut] {
        KeyboardShortcutRegistry.shared.shortcuts(for: currentContexts())
            .filter { $0.action != .openSettings }
    }

    private func currentSectionTitle() -> String {
        AppEnvironment.shared?.activeSection?.title ?? "Section"
    }

    private func makeMenu(identifier: UIMenu.Identifier, shortcuts: [KeyboardShortcut]) -> UIMenu? {
        guard !shortcuts.isEmpty else { return nil }
        let commands = shortcuts.map { shortcut -> UIKeyCommand in
            let payload = shortcutPayload(for: shortcut)
            let command = UIKeyCommand(
                title: shortcut.title,
                image: imageForShortcut(shortcut),
                action: #selector(handleShortcut(_:)),
                input: shortcut.input,
                modifierFlags: shortcut.modifiers,
                propertyList: payload
            )
            command.discoverabilityTitle = shortcut.description
            return command
        }
        return UIMenu(title: "", image: nil, identifier: identifier, options: .displayInline, children: commands)
    }
}
#endif
