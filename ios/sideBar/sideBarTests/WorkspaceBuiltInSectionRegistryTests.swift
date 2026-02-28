import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class WorkspaceBuiltInSectionRegistryTests: XCTestCase {
    func testDefinitionReturnsMappedSection() {
        let registry = WorkspaceBuiltInSectionRegistry(
            definitions: [.chat: makeDefinition(section: .chat)]
        )

        XCTAssertEqual(registry.definition(for: .chat)?.section, .chat)
    }

    func testDefinitionReturnsNilForUnmappedSection() {
        let registry = WorkspaceBuiltInSectionRegistry(
            definitions: [.chat: makeDefinition(section: .chat)]
        )

        XCTAssertNil(registry.definition(for: .notes))
    }

    func testPanelViewUsesMappedDefinitionRenderer() {
        var panelRenderCount = 0
        let registry = WorkspaceBuiltInSectionRegistry(
            definitions: [
                .notes: makeDefinition(
                    section: .notes,
                    panel: { panelRenderCount += 1 }
                )
            ]
        )

        _ = registry.panelView(for: .notes)

        XCTAssertEqual(panelRenderCount, 1)
    }

    func testPanelViewFallbackDoesNotRenderUnmappedDefinition() {
        var panelRenderCount = 0
        let registry = WorkspaceBuiltInSectionRegistry(
            definitions: [
                .chat: makeDefinition(
                    section: .chat,
                    panel: { panelRenderCount += 1 }
                )
            ]
        )

        _ = registry.panelView(for: nil)
        _ = registry.panelView(for: .notes)

        XCTAssertEqual(panelRenderCount, 0)
    }

    func testDetailViewUsesMappedDefinitionRenderer() {
        var detailRenderCount = 0
        let registry = WorkspaceBuiltInSectionRegistry(
            definitions: [
                .tasks: makeDefinition(
                    section: .tasks,
                    detail: { detailRenderCount += 1 }
                )
            ]
        )

        _ = registry.detailView(for: .tasks)

        XCTAssertEqual(detailRenderCount, 1)
    }

    func testDetailViewFallbackDoesNotRenderUnmappedDefinition() {
        var detailRenderCount = 0
        let registry = WorkspaceBuiltInSectionRegistry(
            definitions: [
                .websites: makeDefinition(
                    section: .websites,
                    detail: { detailRenderCount += 1 }
                )
            ]
        )

        _ = registry.detailView(for: nil)
        _ = registry.detailView(for: .notes)

        XCTAssertEqual(detailRenderCount, 0)
    }

    private func makeDefinition(
        section: AppSection,
        panel: (() -> Void)? = nil,
        detail: (() -> Void)? = nil
    ) -> SectionDefinition {
        SectionDefinition(
            section: section,
            panelView: {
                panel?()
                return AnyView(EmptyView())
            },
            detailView: {
                detail?()
                return AnyView(EmptyView())
            },
            phoneSelection: { Binding(get: { nil }, set: { _ in }) }
        )
    }
}
