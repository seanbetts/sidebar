import SwiftUI

/// Central registry for built-in section panel/detail renderers.
@MainActor
struct WorkspaceBuiltInSectionRegistry {
    private let definitions: [AppSection: SectionDefinition]

    init(definitions: [AppSection: SectionDefinition]) {
        self.definitions = definitions
    }

    func definition(for section: AppSection) -> SectionDefinition? {
        definitions[section]
    }

    func panelView(for section: AppSection?) -> AnyView {
        guard let section else {
            return AnyView(SidebarPanelPlaceholder(title: "Select a section"))
        }
        guard let definition = definitions[section] else {
            return AnyView(SidebarPanelPlaceholder(title: section.title))
        }
        return definition.panelView()
    }

    func detailView(for section: AppSection?) -> AnyView {
        guard let section else {
            return AnyView(WelcomeEmptyView())
        }
        guard let definition = definitions[section] else {
            return AnyView(WelcomeEmptyView())
        }
        return definition.detailView()
    }
}
