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

    func testStoreLoadsSnapshotForMatchingUser() {
        let defaults = makeDefaults()
        let store = WorkspaceRestorationStore(userDefaults: defaults)
        let snapshot = DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: "user-1",
            family: .phone,
            updatedAt: Date(timeIntervalSince1970: 1),
            phoneRoute: PhoneWorkspaceRoute(section: .notes, detail: nil),
            splitWorkspace: nil
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(family: .phone, expectedUserId: "user-1"), snapshot)
    }

    func testStoreRejectsSnapshotForDifferentUser() {
        let defaults = makeDefaults()
        let store = WorkspaceRestorationStore(userDefaults: defaults)
        let snapshot = DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: "user-1",
            family: .phone,
            updatedAt: Date(timeIntervalSince1970: 1),
            phoneRoute: PhoneWorkspaceRoute(section: .notes, detail: nil),
            splitWorkspace: nil
        )

        store.save(snapshot)

        XCTAssertNil(store.load(family: .phone, expectedUserId: "user-2"))
    }

    func testStoreReturnsNilForCorruptedSnapshot() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppStorageKeys.workspaceRestorationPhone)
        let store = WorkspaceRestorationStore(userDefaults: defaults)

        XCTAssertNil(store.load(family: .phone, expectedUserId: "user-1"))
    }

    func testStoreClearsOneFamilyWithoutClearingTheOther() {
        let defaults = makeDefaults()
        let store = WorkspaceRestorationStore(userDefaults: defaults)
        let phone = DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: "user-1",
            family: .phone,
            updatedAt: Date(timeIntervalSince1970: 1),
            phoneRoute: PhoneWorkspaceRoute(section: .chat, detail: nil),
            splitWorkspace: nil
        )
        let workspace = DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: "user-1",
            family: .workspace,
            updatedAt: Date(timeIntervalSince1970: 2),
            phoneRoute: nil,
            splitWorkspace: SplitWorkspaceSnapshot(
                sidebarSelection: .tasks,
                primaryDescriptor: .builtIn(.tasks),
                secondaryDescriptor: .builtIn(.chat),
                focusedPane: .primary,
                isLeftPanelExpanded: true,
                isWorkspaceExpanded: false
            )
        )

        store.save(phone)
        store.save(workspace)
        store.clear(family: .phone)

        XCTAssertNil(store.load(family: .phone, expectedUserId: "user-1"))
        XCTAssertEqual(store.load(family: .workspace, expectedUserId: "user-1"), workspace)
    }

    func testDueTodayMarkerMatchesUserAndLocalDate() {
        let defaults = makeDefaults()
        let store = WorkspaceRestorationStore(userDefaults: defaults)

        store.recordDueTodayAutoOpen(userId: "user-1", localDateKey: "2026-05-09")

        XCTAssertTrue(store.hasDueTodayAutoOpened(userId: "user-1", localDateKey: "2026-05-09"))
        XCTAssertFalse(store.hasDueTodayAutoOpened(userId: "user-2", localDateKey: "2026-05-09"))
        XCTAssertFalse(store.hasDueTodayAutoOpened(userId: "user-1", localDateKey: "2026-05-10"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WorkspaceRestorationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
