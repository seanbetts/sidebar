import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#endif

extension ContentView {
    func refreshWeatherIfPossible() async {
        guard environment.authState == .active else { return }
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
            return environment.tasksViewModel.phoneDetailRouteId == nil
        case .settings:
            return true
        }
    }

    func applyInitialSelectionIfNeeded() {
        guard !didSetInitialSelection else { return }
        didSetInitialSelection = true
#if os(iOS)
        if horizontalSizeClass == .compact {
            phoneSelection = .tasks
            sidebarSelection = .tasks
            primarySection = .tasks
        } else {
            primarySection = nil
            secondarySection = .chat
            lastNonChatSection = nil
            isLeftPanelExpanded = false
        }
#else
        primarySection = .notes
        secondarySection = .chat
        lastNonChatSection = .notes
        sidebarSelection = .notes
        isLeftPanelExpanded = true
#endif
        DispatchQueue.main.async {
            hasCompletedInitialSetup = true
        }
        updateActiveSection()
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
}
