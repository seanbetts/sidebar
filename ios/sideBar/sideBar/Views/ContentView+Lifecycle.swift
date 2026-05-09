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
struct WorkspaceExpandedChangePlan: Equatable {
    let isLeftPanelExpanded: Bool
    let previousLeftPanelExpanded: Bool?
    let clearExpandedByRotation: Bool
}
struct WorkspaceRotationPlan: Equatable {
    let lastWorkspaceIsPortrait: Bool
    let isWorkspaceExpanded: Bool?
    let isWorkspaceExpandedByRotation: Bool?
}
struct WorkspaceItemClosePlan: Equatable {
    let isWorkspaceExpanded: Bool
    let isWorkspaceExpandedByRotation: Bool
}
enum ScratchpadPresentationStyle: Equatable {
    case anchoredPopover
    case sheet
}
enum WorkspaceBehaviorPolicy {
    static func makeWorkspaceExpandedChangePlan(
        isExpanded: Bool,
        isLeftPanelExpanded: Bool,
        previousLeftPanelExpanded: Bool?
    ) -> WorkspaceExpandedChangePlan {
        if isExpanded {
            let nextPrevious = previousLeftPanelExpanded ?? isLeftPanelExpanded
            return WorkspaceExpandedChangePlan(
                isLeftPanelExpanded: false,
                previousLeftPanelExpanded: nextPrevious,
                clearExpandedByRotation: false
            )
        }
        guard let previousLeftPanelExpanded else {
            return WorkspaceExpandedChangePlan(
                isLeftPanelExpanded: isLeftPanelExpanded,
                previousLeftPanelExpanded: nil,
                clearExpandedByRotation: false
            )
        }
        return WorkspaceExpandedChangePlan(
            isLeftPanelExpanded: previousLeftPanelExpanded,
            previousLeftPanelExpanded: nil,
            clearExpandedByRotation: true
        )
    }

    static func makeWorkspaceRotationPlan(
        isIPad: Bool,
        previousIsPortrait: Bool?,
        size: CGSize,
        primaryWorkspaceSection: AppSection?,
        isWorkspaceExpanded: Bool,
        isWorkspaceExpandedByRotation: Bool
    ) -> WorkspaceRotationPlan? {
        guard isIPad else { return nil }
        let isPortrait = size.height >= size.width
        guard previousIsPortrait != isPortrait else { return nil }

        guard let primaryWorkspaceSection,
              AppSection.primaryNavigationSections.contains(primaryWorkspaceSection) else {
            return WorkspaceRotationPlan(
                lastWorkspaceIsPortrait: isPortrait,
                isWorkspaceExpanded: nil,
                isWorkspaceExpandedByRotation: nil
            )
        }

        if isPortrait, !isWorkspaceExpanded {
            return WorkspaceRotationPlan(
                lastWorkspaceIsPortrait: isPortrait,
                isWorkspaceExpanded: true,
                isWorkspaceExpandedByRotation: true
            )
        }
        if !isPortrait, isWorkspaceExpandedByRotation {
            return WorkspaceRotationPlan(
                lastWorkspaceIsPortrait: isPortrait,
                isWorkspaceExpanded: false,
                isWorkspaceExpandedByRotation: false
            )
        }
        return WorkspaceRotationPlan(
            lastWorkspaceIsPortrait: isPortrait,
            isWorkspaceExpanded: nil,
            isWorkspaceExpandedByRotation: nil
        )
    }

    static func shouldShowExpandButton(
        workspaceColumn: WorkspaceColumn,
        isPhoneIdiom: Bool
    ) -> Bool {
        guard workspaceColumn == .primary else { return false }
        return !isPhoneIdiom
    }

    static func scratchpadPresentationStyle(isPhoneIdiom: Bool) -> ScratchpadPresentationStyle {
        if isPhoneIdiom {
            return .sheet
        }
        return .anchoredPopover
    }

    static func makeWorkspaceItemClosePlan(
        isWorkspaceExpanded: Bool,
        isWorkspaceExpandedByRotation: Bool
    ) -> WorkspaceItemClosePlan {
        WorkspaceItemClosePlan(
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false
        )
    }
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
        case .skillsStore:
            if environment.settingsViewModel.settings == nil {
                await environment.settingsViewModel.load()
            }
            await environment.settingsViewModel.loadSkills()
        case .chat, .notes, .tasks, .websites, .files, .settings:
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
        isSectionVisibleInWorkspace(.files)
    }

    var isPhonePanelListVisible: Bool {
        guard isCompact else { return false }
        switch compactWorkspaceSection {
        case .chat:
            return environment.chatViewModel.selectedConversationId == nil
                && !environment.chatViewModel.isDraftConversationActive
        case .notes:
            return environment.notesRuntime.viewModel.selectedNoteId == nil
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
        guard environment.authState == .active, environment.isProtectedContentReady else { return }
        guard !didSetInitialSelection else { return }
        didSetInitialSelection = true
        Task {
            if await applyInitialLaunchDestinationIfAvailable() {
                ensureChatSidebarVisibleIfNeeded(for: sidebarSelection)
                DispatchQueue.main.async {
                    hasCompletedInitialSetup = true
                }
                updateActiveSection()
                return
            }
            applyDefaultInitialSelection()
        }
    }

    func applyDefaultInitialSelection() {
#if os(iOS)
        if horizontalSizeClass == .compact {
            phoneSelection = .chat
            sidebarSelection = .chat
            environment.workspaceStore.dispatch(.setLayout(.compact), source: "initial_selection_layout")
            environment.workspaceStore.dispatch(.selectSection(.chat), source: "initial_selection_chat")
        } else {
            sidebarSelection = .chat
            isLeftPanelExpanded = true
            environment.workspaceStore.dispatch(.setLayout(.split), source: "initial_selection_layout")
            environment.workspaceStore.dispatch(.selectSection(.chat), source: "initial_selection_chat")
        }
#else
        let plan = Self.makeMacInitialSelectionPlan(pendingSelection: environment.commandSelection)
        sidebarSelection = plan.sidebarSelection
        environment.workspaceStore.dispatch(.setLayout(.split), source: "initial_selection_layout")
        environment.workspaceStore.dispatch(
            .selectSection(plan.sidebarSelection),
            source: "initial_selection_section"
        )
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
    }

    func updateActiveSection() {
        let section = resolvedActiveSectionForWorkspace
        environment.activeSection = section
        Task {
            await environment.refreshVisibleSectionChange(to: section)
        }
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
        phoneSelection: AppSection,
        isCompactPhoneMoreRootVisible: Bool
    ) -> Bool {
        guard isPhoneIdiom else { return false }
        guard !isCompactPhoneMoreRootVisible else { return false }
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
        guard let newValue else { return }
        #if !os(macOS)
        guard horizontalSizeClass != .compact else {
            updateActiveSection()
            return
        }
        #endif

        if environment.workspaceStore.state.sidebarSelection != newValue {
            environment.workspaceStore.dispatch(
                .selectSection(newValue),
                source: "sidebar_selection_change"
            )
        }
        updateActiveSection()
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
            let selectedSection = compactWorkspaceSection
            sidebarSelection = selectedSection
            environment.workspaceStore.dispatch(.setLayout(.split), source: "horizontal_size_class_change")
            environment.workspaceStore.dispatch(
                .selectSection(selectedSection),
                source: "horizontal_size_class_change"
            )
        } else if oldValue != .compact, newValue == .compact {
            let compactSelection = environment.workspaceStore.state.sidebarSelection ?? .chat
            phoneSelection = compactSelection
            environment.workspaceStore.dispatch(.setLayout(.compact), source: "horizontal_size_class_change")
            environment.workspaceStore.dispatch(
                .selectSection(compactSelection),
                source: "horizontal_size_class_change"
            )
        }
        updateActiveSection()
    }
    #endif
    static func makeInitialPhoneChatAction(
        selectedConversationId: String?
    ) -> InitialPhoneChatAction {
        .none
    }

    @MainActor
    func ensureInitialPhoneChatInterfaceIfNeeded() async {
        #if os(iOS)
        guard shouldStartInitialPhoneChatFlow else { return }
        didEnsureInitialPhoneChatInterface = true
        guard !didInitialPhoneChatFlowGetSuperseded else { return }
        await performInitialPhoneChatAction()
        #endif
    }

    #if os(iOS)
    private var shouldStartInitialPhoneChatFlow: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        guard horizontalSizeClass == .compact else { return false }
        guard environment.authState == .active else { return false }
        guard compactWorkspaceSection == .chat else { return false }
        guard !didEnsureInitialPhoneChatInterface else { return false }
        guard environment.commandSelection == nil else { return false }
        guard !environment.pendingNewTaskDeepLink,
              !environment.pendingNewNoteDeepLink,
              !environment.pendingScratchpadDeepLink,
              !environment.pendingMorningDigestDeepLink else { return false }
        return true
    }

    private var didInitialPhoneChatFlowGetSuperseded: Bool {
        guard compactWorkspaceSection == .chat else { return true }
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
