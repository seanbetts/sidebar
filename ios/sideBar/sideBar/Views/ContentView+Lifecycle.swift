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

struct DesktopSidebarSelectionPlan: Equatable {
    let primarySection: AppSection?
    let secondarySection: AppSection?
    let lastNonChatSection: AppSection?
}

enum InitialPhoneChatAction: Equatable {
    case openDraftConversation
    case none
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
        case .skillsStore:
            if environment.settingsViewModel.settings == nil {
                await environment.settingsViewModel.load()
            }
            await environment.settingsViewModel.loadSkills()
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

    var isDesktopLikeLayout: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass != .compact
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
                && !environment.chatViewModel.isDraftConversationActive
        case .notes:
            return environment.notesViewModel.selectedNoteId == nil
        case .files:
            return environment.ingestionViewModel.selectedFileId == nil
        case .websites:
            return environment.websitesViewModel.selectedWebsiteId == nil
        case .tasks:
            return environment.tasksPhoneDetailRouteId == nil
        case .skillsStore:
            return true
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
            isLeftPanelExpanded = true
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
        ensureChatSidebarVisibleIfNeeded(for: sidebarSelection)
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

    static func makeDesktopSidebarSelectionPlan(
        currentPrimarySection: AppSection?,
        currentSecondarySection: AppSection?,
        currentLastNonChatSection: AppSection?,
        selectedSection: AppSection
    ) -> DesktopSidebarSelectionPlan {
        if selectedSection == .chat {
            return DesktopSidebarSelectionPlan(
                primarySection: nil,
                secondarySection: .chat,
                lastNonChatSection: currentLastNonChatSection
            )
        }

        if currentPrimarySection == .chat {
            return DesktopSidebarSelectionPlan(
                primarySection: .chat,
                secondarySection: selectedSection,
                lastNonChatSection: selectedSection
            )
        }

        return DesktopSidebarSelectionPlan(
            primarySection: selectedSection,
            secondarySection: currentSecondarySection,
            lastNonChatSection: selectedSection
        )
    }

    static func shouldDisplayPhoneFloatingActionDock(
        isPhoneIdiom: Bool,
        isPhonePanelListVisible: Bool,
        phoneSelection: AppSection
    ) -> Bool {
        guard isPhoneIdiom else { return false }
        if isPhonePanelListVisible {
            return AppSection.primaryNavigationSections.contains(phoneSelection)
                && phoneSelection != .skillsStore
        }
        // In compact tasks detail routes, keep showing the dock for quick add.
        return phoneSelection == .tasks
    }

    static func shouldAutoExpandChatSidebar(
        section: AppSection?,
        isDesktopLikeLayout: Bool
    ) -> Bool {
        guard isDesktopLikeLayout else { return false }
        return section == .chat
    }

    func handleSidebarSelectionChange(_ newValue: AppSection?) {
        if let newValue {
            environment.focusedSection = newValue
            ensureChatSidebarVisibleIfNeeded(for: newValue)
        }
        updateActiveSection()

        guard let newValue else { return }
        #if !os(macOS)
        guard horizontalSizeClass != .compact else { return }
        #endif

        let plan = Self.makeDesktopSidebarSelectionPlan(
            currentPrimarySection: primarySection,
            currentSecondarySection: secondarySection,
            currentLastNonChatSection: lastNonChatSection,
            selectedSection: newValue
        )
        primarySection = plan.primarySection
        secondarySection = plan.secondarySection
        lastNonChatSection = plan.lastNonChatSection
    }

    func ensureChatSidebarVisibleIfNeeded(for section: AppSection?) {
        guard Self.shouldAutoExpandChatSidebar(
            section: section,
            isDesktopLikeLayout: isDesktopLikeLayout
        ) else { return }
        if !isLeftPanelExpanded {
            isLeftPanelExpanded = true
        }
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
        selectedConversationId: String?
    ) -> InitialPhoneChatAction {
        if selectedConversationId == nil {
            return .openDraftConversation
        }
        return .none
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
        case .openDraftConversation:
            await environment.chatViewModel.openDraftConversation()
        case .none:
            break
        }
    }
    #endif
}
