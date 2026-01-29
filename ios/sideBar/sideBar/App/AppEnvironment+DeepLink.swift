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
            handleTasksDeepLink(url: url, logger: logger)
        case "notes":
            handleNotesDeepLink(url: url, logger: logger)
        case "files":
            commandSelection = .files
        case "chat":
            commandSelection = .chat
        default:
            logger.info("Unhandled deep link host: \(url.host ?? "", privacy: .public)")
        }
    }

    private func handleTasksDeepLink(url: URL, logger: Logger) {
        commandSelection = .tasks
        if url.path == "/today" {
            Task {
                await tasksViewModel.load(selection: .today, force: true)
            }
            #if !os(macOS)
            tasksViewModel.phoneDetailRouteId = TaskSelection.today.cacheKey
            #endif
        } else if url.path == "/new" {
            logger.info("Deep link to new task")
            pendingNewTaskDeepLink = true
            #if !os(macOS)
            tasksViewModel.phoneDetailRouteId = TaskSelection.today.cacheKey
            #endif
            if isTasksFocused {
                pendingNewTaskDeepLink = false
                tasksViewModel.startNewTask()
            }
        }
    }

    private func handleNotesDeepLink(url: URL, logger: Logger) {
        commandSelection = .notes
        let path = url.path
        if path == "/new" {
            logger.info("Deep link to new note")
            pendingNewNoteDeepLink = true
        } else if !path.isEmpty && path != "/" {
            // Path format: /path/to/note.md
            let noteId = String(path.dropFirst()) // Remove leading slash
            logger.info("Deep link to note: \(noteId, privacy: .public)")
            Task {
                await notesViewModel.loadNote(id: noteId)
            }
        }
    }
}
