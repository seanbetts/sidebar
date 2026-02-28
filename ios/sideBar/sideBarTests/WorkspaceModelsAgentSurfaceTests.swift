import XCTest
@testable import sideBar

final class WorkspaceModelsAgentSurfaceTests: XCTestCase {
    func testSurfaceTypeMapsKnownRawValue() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: "map",
            surfaceId: "surface-map-1"
        )

        XCTAssertEqual(descriptor.surfaceType, .map)
    }

    func testSurfaceTypeFallsBackToActionPanelForUnknownRawValue() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: "custom-widget",
            surfaceId: "surface-custom-1"
        )

        XCTAssertEqual(descriptor.surfaceType, .actionPanel)
    }

    func testCapabilitiesDefaultAllEnabled() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-md-1"
        )

        XCTAssertTrue(descriptor.capabilities.canRefresh)
        XCTAssertTrue(descriptor.capabilities.canClose)
        XCTAssertTrue(descriptor.capabilities.canPin)
        XCTAssertTrue(descriptor.capabilities.canInspectData)
    }
}
