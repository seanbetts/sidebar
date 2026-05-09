import XCTest
@testable import sideBar

@MainActor
final class WorkspaceRestorationStoreTests: XCTestCase {
    func testPhoneSnapshotRoundTripsThroughJSON() throws {
        let snapshot = DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: "user-1",
            family: .phone,
            updatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            phoneRoute: PhoneWorkspaceRoute(
                section: .chat,
                detail: .conversation(id: "conversation-1")
            ),
            splitWorkspace: nil
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DeviceWorkspaceSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testWorkspaceSnapshotConvertsBuiltInDescriptors() {
        let split = SplitWorkspaceSnapshot(
            sidebarSelection: .notes,
            primaryDescriptor: .init(descriptor: .builtIn(.notes)),
            secondaryDescriptor: .init(descriptor: .builtIn(.chat)),
            focusedPane: .primary,
            isLeftPanelExpanded: true,
            isWorkspaceExpanded: false
        )

        XCTAssertEqual(split.primaryDescriptor.workspaceDescriptor, .builtIn(.notes))
        XCTAssertEqual(split.secondaryDescriptor?.workspaceDescriptor, .builtIn(.chat))
    }

    func testWorkspaceSnapshotStoresAgentSurfaceAsEmptyDescriptor() {
        let surface = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-1",
            title: "Generated"
        )

        let snapshot = WorkspaceDescriptorSnapshot(descriptor: .agentSurface(surface))

        XCTAssertEqual(snapshot, .empty)
        XCTAssertEqual(snapshot.workspaceDescriptor, .empty)
    }
}
