import Foundation
import os
#if os(iOS)
import UIKit
#endif

@MainActor
extension AppEnvironment {
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "sidebar" else { return }
        let logger = Logger(subsystem: "sideBar", category: "DeepLink")
        logger.info("Handling deep link: \(url.absoluteString, privacy: .public)")
        switch url.host {
        case "tasks":
            commandSelection = .tasks
            if url.path == "/new" {
                logger.info("Deep link to new task")
                pendingNewTaskDeepLink = true
                if isTasksFocused {
                    pendingNewTaskDeepLink = false
                    tasksViewModel.startNewTask()
                }
            }
        case "notes":
            commandSelection = .notes
        case "files":
            commandSelection = .files
        case "chat":
            commandSelection = .chat
        default:
            logger.info("Unhandled deep link host: \(url.host ?? "", privacy: .public)")
        }
    }
}
