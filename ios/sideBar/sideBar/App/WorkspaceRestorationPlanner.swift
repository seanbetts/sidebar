import Foundation

struct PhoneWorkspaceRestorationPlan: Equatable {
    var section: AppSection
    var detail: PhoneWorkspaceDetail?

    var shouldOpenEmptyChatDraft: Bool {
        false
    }
}

struct SplitWorkspaceRestorationPlan: Equatable {
    var sidebarSelection: AppSection
    var primaryDescriptor: WorkspaceContentDescriptor
    var secondaryDescriptor: WorkspaceContentDescriptor
    var focusedPane: WorkspacePane
    var isLeftPanelExpanded: Bool
    var isWorkspaceExpanded: Bool
}

enum InitialLaunchDestination: Equatable {
    case externalIntent
    case dueTodayTasks
    case restoredSnapshot
    case fallbackChat
}

enum WorkspaceRestorationPlanner {
    static func makePhoneRoute(
        section: AppSection,
        selectedConversationId: String?,
        isDraftConversationActive: Bool,
        hasMeaningfulChatDraft: Bool,
        selectedNoteId: String?,
        selectedTaskRouteId: String?,
        selectedWebsiteId: String?,
        selectedFileId: String?
    ) -> PhoneWorkspaceRoute {
        let detail: PhoneWorkspaceDetail?
        switch section {
        case .chat:
            if let selectedConversationId {
                detail = .conversation(id: selectedConversationId)
            } else if isDraftConversationActive && hasMeaningfulChatDraft {
                detail = .chatDraft
            } else {
                detail = nil
            }
        case .notes:
            detail = selectedNoteId.map { .note(id: $0) }
        case .tasks:
            detail = selectedTaskRouteId.map { .taskRoute(id: $0) }
        case .websites:
            detail = selectedWebsiteId.map { .website(id: $0) }
        case .files:
            detail = selectedFileId.map { .file(id: $0) }
        case .skillsStore, .settings:
            detail = nil
        }

        return PhoneWorkspaceRoute(section: section, detail: detail)
    }

    static func makePhonePlan(
        route: PhoneWorkspaceRoute,
        hasMeaningfulChatDraft: Bool = false
    ) -> PhoneWorkspaceRestorationPlan {
        let detail: PhoneWorkspaceDetail?
        if route.detail == .chatDraft && !hasMeaningfulChatDraft {
            detail = nil
        } else {
            detail = route.detail
        }
        return PhoneWorkspaceRestorationPlan(
            section: route.section,
            detail: detail
        )
    }

    static func makeWorkspacePlan(
        snapshot: SplitWorkspaceSnapshot
    ) -> SplitWorkspaceRestorationPlan {
        let primary = snapshot.primaryDescriptor.workspaceDescriptor
        let secondary = snapshot.secondaryDescriptor?.workspaceDescriptor ?? .empty
        let hasRestorableContent = primary != .empty || secondary != .empty

        guard hasRestorableContent else {
            return chatFallbackWorkspacePlan(isLeftPanelExpanded: snapshot.isLeftPanelExpanded)
        }

        let sidebar = snapshot.sidebarSelection
            ?? WorkspaceLegacySectionAdapter.section(from: primary)
            ?? WorkspaceLegacySectionAdapter.section(from: secondary)
            ?? .chat

        return SplitWorkspaceRestorationPlan(
            sidebarSelection: sidebar,
            primaryDescriptor: primary,
            secondaryDescriptor: secondary,
            focusedPane: snapshot.focusedPane,
            isLeftPanelExpanded: snapshot.isLeftPanelExpanded,
            isWorkspaceExpanded: snapshot.isWorkspaceExpanded
        )
    }

    static func chatFallbackWorkspacePlan(
        isLeftPanelExpanded: Bool = true
    ) -> SplitWorkspaceRestorationPlan {
        SplitWorkspaceRestorationPlan(
            sidebarSelection: .chat,
            primaryDescriptor: .empty,
            secondaryDescriptor: .builtIn(.chat),
            focusedPane: .secondary,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: false
        )
    }

    static func shouldSkipRestorationForExternalIntent(
        commandSelection: AppSection?,
        hasQueuedProtectedDeepLinks: Bool,
        hasPendingNewTaskDeepLink: Bool,
        hasPendingNewNoteDeepLink: Bool,
        hasPendingScratchpadDeepLink: Bool,
        hasPendingMorningDigestDeepLink: Bool
    ) -> Bool {
        commandSelection != nil
            || hasQueuedProtectedDeepLinks
            || hasPendingNewTaskDeepLink
            || hasPendingNewNoteDeepLink
            || hasPendingScratchpadDeepLink
            || hasPendingMorningDigestDeepLink
    }

    static func makeInitialLaunchDestination(
        hasExternalIntent: Bool,
        todayTaskCount: Int,
        hasOpenedDueToday: Bool,
        hasRestorationSnapshot: Bool
    ) -> InitialLaunchDestination {
        if hasExternalIntent {
            return .externalIntent
        }
        if todayTaskCount > 0 && !hasOpenedDueToday {
            return .dueTodayTasks
        }
        if hasRestorationSnapshot {
            return .restoredSnapshot
        }
        return .fallbackChat
    }
}
