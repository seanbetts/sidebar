import XCTest
import sideBarShared
@testable import sideBar

final class WorkspaceSurfaceActionPresentationTests: XCTestCase {
    func testSingleTargetUsesBareButtonPresentation() {
        let presentation = WorkspaceSurfaceActionPresentation.from(targets: [makeTarget(id: "prompt-preview")])

        XCTAssertEqual(
            presentation,
            .singleButton(makeTarget(id: "prompt-preview"))
        )
    }

    func testMultipleTargetsUseGroupedPresentation() {
        let first = makeTarget(id: "surface-1")
        let second = makeTarget(id: "surface-2")

        let presentation = WorkspaceSurfaceActionPresentation.from(targets: [first, second])

        XCTAssertEqual(
            presentation,
            .grouped([first, second])
        )
    }

    private func makeTarget(id: String) -> ToolResultWorkspaceSurfaceTarget {
        ToolResultWorkspaceSurfaceTarget(
            surface: AgentWorkspaceSurfaceDescriptor(
                type: .markdown,
                surfaceId: id,
                title: "System Prompt Preview"
            ),
            pane: .primary,
            label: "Show System Prompt Preview",
            appIcon: AppIcon.Skills.promptPreview
        )
    }
}
