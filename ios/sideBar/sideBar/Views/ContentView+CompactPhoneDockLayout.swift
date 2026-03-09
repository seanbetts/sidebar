import SwiftUI
import sideBarShared

extension ContentView {
    static func shouldDisplayCompactPhoneSearchDock(
        isCompact: Bool,
        isPhoneIdiom: Bool,
        isPhonePanelListVisible: Bool,
        phoneSelection: AppSection,
        isCompactPhoneMoreRootVisible: Bool
    ) -> Bool {
        guard isCompact else { return false }
        guard isPhoneIdiom else { return false }
        guard !isCompactPhoneMoreRootVisible else { return false }
        guard isPhonePanelListVisible else { return false }
        return compactPhoneBottomSearchSections.contains(phoneSelection)
    }

    static func isCompactPhoneSearchDockExpanded(
        searchText: String,
        isSearchExplicitlyExpanded: Bool,
        isSearchFocused: Bool
    ) -> Bool {
        isSearchExplicitlyExpanded || isSearchFocused || !searchText.trimmed.isEmpty
    }

    static func shouldCollapseCompactPhoneSearchDockActions(
        actionCount: Int,
        isSearchExpanded: Bool
    ) -> Bool {
        isSearchExpanded && actionCount > 1
    }

    static func shouldResetCompactPhoneSearchDock(
        previousSection: AppSection,
        nextSection: AppSection
    ) -> Bool {
        previousSection != nextSection
    }

    static func compactPhoneSearchDockBottomPadding(
        isSoftwareKeyboardVisible: Bool,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat {
        guard !isSoftwareKeyboardVisible else { return DesignTokens.Spacing.sm }
        return max(72, 42 + bottomSafeAreaInset)
    }

    static func shouldAttachCompactPhoneSearchDockToKeyboard(
        isSoftwareKeyboardVisible: Bool,
        searchText: String,
        isSearchExplicitlyExpanded: Bool
    ) -> Bool {
        guard isSoftwareKeyboardVisible else { return false }
        return isCompactPhoneSearchDockExpanded(
            searchText: searchText,
            isSearchExplicitlyExpanded: isSearchExplicitlyExpanded,
            isSearchFocused: false
        )
    }

    static func shouldHandleCompactPhoneSearchDockBackgroundTap(
        isSearchExplicitlyExpanded: Bool,
        isCompactPhoneMoreRootVisible: Bool
    ) -> Bool {
        isSearchExplicitlyExpanded && !isCompactPhoneMoreRootVisible
    }
}
