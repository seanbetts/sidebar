import Foundation
import os
import sideBarShared

@MainActor
extension AppEnvironment {
    func handleDeepLink(_ url: URL) {
        if PasswordRecoveryURLMatcher.matches(url) {
            Task { [weak self] in
                await self?.beginPasswordRecovery(from: url)
            }
            return
        }

        guard url.scheme == "sidebar" else { return }
        let logger = Logger(subsystem: "sideBar", category: "DeepLink")
        guard !(isAuthenticated && !isProtectedContentReady) else {
            logger.info("Queueing protected deep link until auth is ready: \(url.absoluteString, privacy: .public)")
            queueProtectedDeepLink(url)
            return
        }
        logger.info("Handling deep link: \(url.absoluteString, privacy: .public)")
        AppSentry.recordAction(
            category: "deep_link",
            name: deepLinkActionName(for: url),
            data: ["host": url.host ?? "unknown"]
        )
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "deep_link",
            stage: "handle",
            message: "Handling deep link.",
            metadata: ["url": url.absoluteString]
        )
        handleSidebarDeepLink(url: url, logger: logger)
    }

    private func handleSidebarDeepLink(url: URL, logger: Logger) {
        switch url.host {
        case "tasks":
            handleTasksDeepLink(url: url, logger: logger)
        case "digest":
            handleDigestDeepLink(url: url, logger: logger)
        case "notes":
            handleNotesDeepLink(url: url, logger: logger)
        case "websites":
            handleWebsitesDeepLink(url: url, logger: logger)
        case "files":
            handleFilesDeepLink(url: url, logger: logger)
        case "chat":
            handleChatDeepLink(url: url, logger: logger)
        case "scratchpad":
            handleScratchpadDeepLink(logger: logger)
        default:
            logger.info("Unhandled deep link host: \(url.host ?? "", privacy: .public)")
        }
    }

    private func handleTasksDeepLink(url: URL, logger: Logger) {
        routeWorkspaceSelection(to: .tasks, source: "deeplink_tasks")
        if url.path == "/today" {
            Task {
                await tasksViewModel.load(selection: .today, force: true)
            }
            #if !os(macOS)
            tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
            #endif
        } else if url.path == "/new" {
            logger.info("Deep link to new task")
            pendingNewTaskDeepLink = true
            #if !os(macOS)
            tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
            #endif
            if isTasksFocused {
                pendingNewTaskDeepLink = false
                tasksViewModel.startNewTask()
            }
        }
    }

    private func handleNotesDeepLink(url: URL, logger: Logger) {
        routeWorkspaceSelection(to: .notes, source: "deeplink_notes")
        let path = url.path
        if path == "/new" {
            logger.info("Deep link to new note")
            pendingNewNoteDeepLink = true
        } else if !path.isEmpty && path != "/" {
            // Path format: /path/to/note.md
            let rawNoteId = String(path.dropFirst())
            let noteId = rawNoteId.removingPercentEncoding ?? rawNoteId
            logger.info("Deep link to note: \(noteId, privacy: .public)")
            Task {
                await notesViewModel.loadNote(id: noteId)
            }
        }
    }

    private func handleWebsitesDeepLink(url: URL, logger: Logger) {
        routeWorkspaceSelection(to: .websites, source: "deeplink_websites")
        let path = url.path
        if !path.isEmpty && path != "/" {
            // Path format: /{websiteId}
            let websiteId = String(path.dropFirst())
            logger.info("Deep link to website: \(websiteId, privacy: .public)")
            Task {
                await websitesViewModel.selectWebsite(id: websiteId)
            }
        }
    }

    private func handleFilesDeepLink(url: URL, logger: Logger) {
        routeWorkspaceSelection(to: .files, source: "deeplink_files")
        let path = url.path
        if !path.isEmpty && path != "/" {
            // Path format: /{fileId}
            let fileId = String(path.dropFirst())
            logger.info("Deep link to file: \(fileId, privacy: .public)")
            Task {
                await ingestionViewModel.selectFile(fileId: fileId)
            }
        }
    }

    private func handleChatDeepLink(url: URL, logger: Logger) {
        routeWorkspaceSelection(to: .chat, source: "deeplink_chat")
        let path = url.path
        if path == "/new" {
            logger.info("Deep link to new chat")
            Task {
                await chatViewModel.startNewConversation()
            }
        } else if !path.isEmpty && path != "/" {
            // Path format: /{chatId}
            let chatId = String(path.dropFirst())
            logger.info("Deep link to chat: \(chatId, privacy: .public)")
            Task {
                await chatViewModel.selectConversation(id: chatId)
            }
        }
    }

    private func handleScratchpadDeepLink(logger: Logger) {
        logger.info("Deep link to scratchpad")
        // Scratchpad is accessed via the chat section
        routeWorkspaceSelection(to: .chat, source: "deeplink_scratchpad")
        pendingScratchpadDeepLink = true
    }

    private func handleDigestDeepLink(url: URL, logger: Logger) {
        logger.info("Deep link to morning digest")
        guard url.path == "/morning" else { return }
        pendingMorningDigestDeepLink = true
    }

    private func deepLinkActionName(for url: URL) -> String {
        switch url.host {
        case "tasks":
            return tasksDeepLinkActionName(path: url.path)
        case "notes":
            return url.path == "/new" ? "Started New Note via Deep Link" : "Opened Notes via Deep Link"
        case "chat":
            return url.path == "/new" ? "Started New Chat via Deep Link" : "Opened Chat via Deep Link"
        case "digest":
            return "Opened Morning Digest via Deep Link"
        case "scratchpad":
            return "Opened Scratchpad via Deep Link"
        case "websites":
            return "Opened Websites via Deep Link"
        case "files":
            return "Opened Files via Deep Link"
        default:
            return "Handled Deep Link"
        }
    }

    private func tasksDeepLinkActionName(path: String) -> String {
        switch path {
        case "/new":
            return "Started New Task via Deep Link"
        case "/today":
            return "Opened Tasks Today via Deep Link"
        default:
            return "Opened Tasks via Deep Link"
        }
    }

    func beginPasswordRecovery(from url: URL) async {
        do {
            try await container.passwordRecoveryManager.startRecoverySession(from: url)
            passwordResetSuccessMessage = nil
            passwordResetSuccessDetail = nil
            passwordResetState = .enterNewPassword
        } catch {
            passwordResetState = nil
        }
    }

    func completePasswordRecovery(newPassword: String) async throws {
        try await container.passwordRecoveryManager.completePasswordReset(newPassword: newPassword)
        passwordResetState = nil
        passwordResetSuccessMessage = "Password updated. Sign in with your new password."
        passwordResetSuccessDetail = nil
        await container.authSession.signOut()
        refreshAuthState()
    }

    func cancelPasswordRecovery() async {
        passwordResetState = nil
        await container.authSession.signOut()
        refreshAuthState()
    }
}
