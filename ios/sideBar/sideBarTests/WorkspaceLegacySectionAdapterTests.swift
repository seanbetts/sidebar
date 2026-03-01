import XCTest
@testable import sideBar

final class WorkspaceLegacySectionAdapterTests: XCTestCase {
    func testSectionMappingReturnsBuiltInSection() {
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.section(from: .builtIn(.notes)),
            .notes
        )
    }

    func testSectionMappingIgnoresEmptyDescriptorAndMapsAgentSurfaceToChat() {
        XCTAssertNil(WorkspaceLegacySectionAdapter.section(from: .empty))
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.section(
                from: .agentSurface(
                    AgentWorkspaceSurfaceDescriptor(type: "map", surfaceId: "surface-1")
                )
            ),
            .chat
        )
    }

    func testSectionMappingHandlesNilDescriptor() {
        XCTAssertNil(WorkspaceLegacySectionAdapter.section(from: nil))
    }
}
