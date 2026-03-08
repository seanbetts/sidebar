import SwiftUI

enum CompactPhoneTab: Hashable {
    case section(AppSection)
    case more
}

extension ContentView {
    static let compactPhoneBottomTabSections: [AppSection] = [
        .chat,
        .notes,
        .tasks,
        .websites
    ]

    static let compactPhoneBottomSearchSections: [AppSection] = [
        .chat,
        .notes,
        .tasks,
        .websites,
        .files,
        .skillsStore
    ]

    static let compactPhoneOverflowSections: [AppSection] = [
        .files,
        .skillsStore
    ]

    var compactPhoneTabs: [CompactPhoneTab] {
        Self.compactPhoneBottomTabSections.map(CompactPhoneTab.section) + [.more]
    }

    var isCompactPhoneMoreRootVisible: Bool {
        isCompact && isPhoneIdiom
            && compactPhoneTabSelection == .more
            && compactPhoneMoreNavigationPath.isEmpty
    }

    func compactPhoneTabSelectionBinding() -> Binding<CompactPhoneTab> {
        Binding(
            get: { compactPhoneTabSelection },
            set: { newValue in
                compactPhoneTabSelection = newValue

                switch newValue {
                case .section(let section):
                    compactPhoneMoreNavigationPath = []
                    phoneSelection = section
                case .more:
                    compactPhoneMoreNavigationPath = []
                }
            }
        )
    }

    func syncCompactPhoneTabSelection(for section: AppSection) {
        guard isCompact && isPhoneIdiom else { return }

        if Self.compactPhoneBottomTabSections.contains(section) {
            compactPhoneTabSelection = .section(section)
            compactPhoneMoreNavigationPath = []
            return
        }

        compactPhoneTabSelection = .more
        compactPhoneMoreNavigationPath = [section]
    }

    func compactPhoneTabTitle(for tab: CompactPhoneTab) -> String {
        switch tab {
        case .section(let section):
            return section.title
        case .more:
            return "More"
        }
    }

    func compactPhoneTabIconName(for tab: CompactPhoneTab) -> String {
        Self.compactPhoneTabIconName(for: tab, phoneIconName: phoneIconName(for:))
    }

    static func compactPhoneTabIconName(
        for tab: CompactPhoneTab,
        phoneIconName: (AppSection) -> String
    ) -> String {
        switch tab {
        case .section(let section):
            return phoneIconName(section)
        case .more:
            return "ellipsis"
        }
    }
}
