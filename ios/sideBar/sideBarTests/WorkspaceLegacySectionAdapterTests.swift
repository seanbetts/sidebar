import XCTest
@testable import sideBar

final class WorkspaceLegacySectionAdapterTests: XCTestCase {
    func testSectionMappingReturnsBuiltInSection() {
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.section(from: .builtIn(.notes)),
            .notes
        )
    }

    func testSectionMappingIgnoresEmptyAndAgentSurfaceDescriptors() {
        XCTAssertNil(WorkspaceLegacySectionAdapter.section(from: .empty))
        XCTAssertNil(
            WorkspaceLegacySectionAdapter.section(
                from: .agentSurface(
                    AgentWorkspaceSurfaceDescriptor(type: "map", surfaceId: "surface-1")
                )
            )
        )
    }

    func testSectionMappingHandlesNilDescriptor() {
        XCTAssertNil(WorkspaceLegacySectionAdapter.section(from: nil))
    }
}
