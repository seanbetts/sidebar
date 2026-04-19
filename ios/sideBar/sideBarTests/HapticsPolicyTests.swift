import XCTest
@testable import sideBar

final class HapticsPolicyTests: XCTestCase {
    override func tearDown() {
        Haptics.resetTestingOverrides()
        super.tearDown()
    }

    func testNotificationSkipsDriverWhenHapticsAreDisabled() {
        let recorder = HapticsTestRecorder()
        Haptics.installTestingOverrides(
            client: recorder.client,
            isEnabled: { false }
        )

        Haptics.notification(.success)

        XCTAssertTrue(recorder.notifications.isEmpty)
    }

    func testImpactSkipsDriverWhenHapticsAreDisabled() {
        let recorder = HapticsTestRecorder()
        Haptics.installTestingOverrides(
            client: recorder.client,
            isEnabled: { false }
        )

        Haptics.impact(.light)

        XCTAssertTrue(recorder.impacts.isEmpty)
    }

    func testSelectionSkipsDriverWhenHapticsAreDisabled() {
        let recorder = HapticsTestRecorder()
        Haptics.installTestingOverrides(
            client: recorder.client,
            isEnabled: { false }
        )

        Haptics.selection()

        XCTAssertEqual(recorder.selectionCount, 0)
    }

    func testNotificationUsesDriverWhenHapticsAreEnabled() {
        let recorder = HapticsTestRecorder()
        Haptics.installTestingOverrides(
            client: recorder.client,
            isEnabled: { true }
        )

        Haptics.notification(.error)

        XCTAssertEqual(recorder.notifications, [.error])
    }

    func testImpactUsesDriverWhenHapticsAreEnabled() {
        let recorder = HapticsTestRecorder()
        Haptics.installTestingOverrides(
            client: recorder.client,
            isEnabled: { true }
        )

        Haptics.impact(.heavy)

        XCTAssertEqual(recorder.impacts, [.heavy])
    }

    func testSelectionUsesDriverWhenHapticsAreEnabled() {
        let recorder = HapticsTestRecorder()
        Haptics.installTestingOverrides(
            client: recorder.client,
            isEnabled: { true }
        )

        Haptics.selection()

        XCTAssertEqual(recorder.selectionCount, 1)
    }

    func testPlatformPolicyDisablesIPadHaptics() {
        XCTAssertFalse(Haptics.isSupported(on: .pad))
    }

    func testPlatformPolicyKeepsIPhoneHapticsEnabled() {
        XCTAssertTrue(Haptics.isSupported(on: .phone))
    }

    func testPlatformPolicyDisablesMacAndOtherDevices() {
        XCTAssertFalse(Haptics.isSupported(on: .other))
    }
}

private final class HapticsTestRecorder {
    private(set) var notifications: [Haptics.NotificationType] = []
    private(set) var impacts: [Haptics.ImpactStyle] = []
    private(set) var selectionCount = 0

    var client: Haptics.Client {
        Haptics.Client(
            notification: { [weak self] type in
                self?.notifications.append(type)
            },
            impact: { [weak self] style in
                self?.impacts.append(style)
            },
            selection: { [weak self] in
                self?.selectionCount += 1
            }
        )
    }
}
