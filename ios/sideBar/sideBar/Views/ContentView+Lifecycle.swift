import SwiftUI
import sideBarShared
import CoreLocation
#if os(iOS)
import UIKit
#endif

struct MacInitialSelectionPlan {
    let primarySection: AppSection?
    let secondarySection: AppSection?
    let lastNonChatSection: AppSection?
    let sidebarSelection: AppSection
    let focusedSection: AppSection?
    let shouldConsumeCommandSelection: Bool
}

enum InitialPhoneChatAction: Equatable {
    case createConversation
}

extension ContentView {
    func refreshWeatherIfPossible() async {
        guard environment.authState == .active else { return }
        if let coordinate = environment.currentLocationViewModel.currentLocationCoordinate {
            await environment.weatherViewModel.load(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            return
        }
        let location = environment.settingsViewModel.settings?.location?.trimmed ?? ""
        guard !location.isEmpty else { return }
        await environment.weatherViewModel.load(location: location)
    }

    func loadPhoneSectionIfNeeded(_ section: AppSection) async {
        switch section {
        case .notes:
            await environment.notesViewModel.loadTree()
        case .websites:
            await environment.websitesViewModel.load()
        case .files:
            await environment.ingestionViewModel.load()
        case .chat:
            await environment.chatViewModel.loadConversations()
        case .tasks, .settings:
            break
        }
    }

    var topSafeAreaBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.background
        #else
        if isCompact && isPhonePanelListVisible {
            return DesignTokens.Colors.surface
        }
        return DesignTokens.Colors.background
        #endif
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isFilesSectionVisible: Bool {
        #if os(macOS)
        return primarySection == .files || secondarySection == .files
        #else
        if isCompact {
            return phoneSelection == .files
        }
        return primarySection == .files || secondarySection == .files
        #endif
    }

    var isPhonePanelListVisible: Bool {
        guard isCompact else { return false }
        switch phoneSelection {
        case .chat:
            return environment.chatViewModel.selectedConversationId == nil
        case .notes:
            return environment.notesViewModel.selectedNoteId == nil
        case .files:
            return environment.ingestionViewModel.selectedFileId == nil
        case .websites:
            return environment.websitesViewModel.selectedWebsiteId == nil
        case .tasks:
            return environment.tasksPhoneDetailRouteId == nil
        case .settings:
            return true
        }
    }

    func applyInitialSelectionIfNeeded() {
        guard !didSetInitialSelection else { return }
        didSetInitialSelection = true
#if os(iOS)
        if horizontalSizeClass == .compact {
            phoneSelection = .chat
            sidebarSelection = .chat
            primarySection = .chat
        } else {
            primarySection = nil
            secondarySection = .chat
            sidebarSelection = .chat
            lastNonChatSection = nil
            isLeftPanelExpanded = false
        }
#else
        let plan = Self.makeMacInitialSelectionPlan(pendingSelection: environment.commandSelection)
        primarySection = plan.primarySection
        secondarySection = plan.secondarySection
        lastNonChatSection = plan.lastNonChatSection
        sidebarSelection = plan.sidebarSelection
        if plan.shouldConsumeCommandSelection {
            environment.focusedSection = plan.focusedSection
            environment.commandSelection = nil
        }
        isLeftPanelExpanded = true
#endif
        DispatchQueue.main.async {
            hasCompletedInitialSetup = true
        }
        updateActiveSection()
#if os(iOS)
        Task { await ensureInitialPhoneChatInterfaceIfNeeded() }
#endif
    }

    func updateActiveSection() {
        #if os(macOS)
        let section = isSettingsPresented ? AppSection.settings : (primarySection ?? sidebarSelection ?? secondarySection)
        #else
        let section: AppSection
        if isSettingsPresented {
            section = .settings
        } else if horizontalSizeClass == .compact {
            section = phoneSelection
        } else {
            section = primarySection ?? sidebarSelection ?? secondarySection ?? .chat
        }
        #endif
        environment.activeSection = section
        #if os(iOS)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }

    var tabBarTint: Color {
        #if os(macOS)
        return Color.accentColor
        #else
        return colorScheme == .dark ? Color.white : Color.black
        #endif
    }

    var tabAccessoryBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.surface
        #else
        return DesignTokens.Colors.surface
        #endif
    }

    var tabAccessoryBorder: Color {
        #if os(macOS)
        return DesignTokens.Colors.border
        #else
        return DesignTokens.Colors.border
        #endif
    }

    var separatorColor: Color {
        #if os(macOS)
        return DesignTokens.Colors.border
        #else
        return DesignTokens.Colors.border
        #endif
    }

    static func makeMacInitialSelectionPlan(pendingSelection: AppSection?) -> MacInitialSelectionPlan {
        guard let pendingSelection, pendingSelection != .settings else {
            return MacInitialSelectionPlan(
                primarySection: nil,
                secondarySection: .chat,
                lastNonChatSection: nil,
                sidebarSelection: .chat,
                focusedSection: nil,
                shouldConsumeCommandSelection: false
            )
        }

        return MacInitialSelectionPlan(
            primarySection: pendingSelection == .chat ? nil : pendingSelection,
            secondarySection: .chat,
            lastNonChatSection: pendingSelection == .chat ? nil : pendingSelection,
            sidebarSelection: pendingSelection,
            focusedSection: pendingSelection,
            shouldConsumeCommandSelection: true
        )
    }

    static func makeRegularLayoutPlanFromCompactSelection(
        phoneSelection: AppSection
    ) -> MacInitialSelectionPlan {
        makeMacInitialSelectionPlan(pendingSelection: phoneSelection)
    }

    static func shouldDisplayPhoneFloatingActionDock(
        isPhoneIdiom: Bool,
        isPhonePanelListVisible: Bool,
        phoneSelection: AppSection
    ) -> Bool {
        guard isPhoneIdiom else { return false }
        if isPhonePanelListVisible {
            return AppSection.primaryNavigationSections.contains(phoneSelection)
        }
        // In compact tasks detail routes, keep showing the dock for quick add.
        return phoneSelection == .tasks
    }

    #if !os(macOS)
    func handleHorizontalSizeClassChange(
        oldValue: UserInterfaceSizeClass?,
        newValue: UserInterfaceSizeClass?
    ) {
        if oldValue == .compact, newValue != .compact {
            let plan = Self.makeRegularLayoutPlanFromCompactSelection(phoneSelection: phoneSelection)
            primarySection = plan.primarySection
            secondarySection = plan.secondarySection
            lastNonChatSection = plan.lastNonChatSection
            sidebarSelection = plan.sidebarSelection
        }
        updateActiveSection()
    }
    #endif

    static func makeInitialPhoneChatAction(
        selectedConversationId _: String?
    ) -> InitialPhoneChatAction {
        return .createConversation
    }

    @MainActor
    func ensureInitialPhoneChatInterfaceIfNeeded() async {
        #if os(iOS)
        guard shouldStartInitialPhoneChatFlow else { return }
        didEnsureInitialPhoneChatInterface = true
        await environment.chatViewModel.loadConversations()
        guard !didInitialPhoneChatFlowGetSuperseded else { return }
        await performInitialPhoneChatAction()
        #endif
    }

    #if os(iOS)
    private var shouldStartInitialPhoneChatFlow: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        guard horizontalSizeClass == .compact else { return false }
        guard environment.authState == .active else { return false }
        guard phoneSelection == .chat else { return false }
        guard !didEnsureInitialPhoneChatInterface else { return false }
        guard environment.commandSelection == nil else { return false }
        guard !environment.pendingNewTaskDeepLink,
              !environment.pendingNewNoteDeepLink,
              !environment.pendingScratchpadDeepLink else { return false }
        return true
    }

    private var didInitialPhoneChatFlowGetSuperseded: Bool {
        guard phoneSelection == .chat else { return true }
        if let commandSelection = environment.commandSelection, commandSelection != .chat {
            return true
        }
        return false
    }

    @MainActor
    private func performInitialPhoneChatAction() async {
        let action = Self.makeInitialPhoneChatAction(
            selectedConversationId: environment.chatViewModel.selectedConversationId
        )
        switch action {
        case .createConversation:
            await environment.chatViewModel.startNewConversation()
        }
    }
    #endif
}
