import Combine
import XCTest
import sideBarShared
@testable import sideBar

final class ThemeManagerTests: XCTestCase {
    private var isolatedDefaults: [TestIsolation.IsolatedUserDefaults] = []
    private static var retainedManagers: [ThemeManager] = []
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        isolatedDefaults.forEach { $0.tearDown() }
        isolatedDefaults.removeAll()
        cancellables.removeAll()
        super.tearDown()
    }

    func testDefaultsToSystemWhenUnset() {
        let (manager, _) = makeThemeManager()
        XCTAssertEqual(manager.mode, .system)
    }

    func testPersistsModeChange() {
        let (manager, defaults) = makeThemeManager()
        manager.mode = .dark

        let stored = defaults.string(forKey: AppStorageKeys.themeMode)
        XCTAssertEqual(stored, ThemeMode.dark.rawValue)
    }

    func testFreshTestManagerStartsWithCleanDefaults() {
        let (firstManager, _) = makeThemeManager()
        firstManager.mode = .dark

        let (secondManager, _) = makeThemeManager()

        XCTAssertEqual(secondManager.mode, .system)
    }

    func testModePublishesOffMainThreadWhenMutatedFromDetachedTask() async throws {
        let (manager, _) = makeThemeManager()
        let expectation = expectation(description: "mode update published")
        let publicationThread = LockedBox<Bool?>(nil)

        manager.$mode
            .dropFirst()
            .sink { _ in
                publicationThread.set(Thread.isMainThread)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let task = Task.detached {
            manager.mode = .dark
        }
        _ = await task.value

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(publicationThread.value, false)
    }

    private func makeThemeManager() -> (ThemeManager, UserDefaults) {
        let isolated = TestIsolation.makeUserDefaults(prefix: "ThemeManagerTests")
        isolatedDefaults.append(isolated)
        let manager = ThemeManager(userDefaults: isolated.defaults)
        // Keep managers alive past the test method scope. On current macOS/XCTest
        // toolchains their deallocation can crash while the memory checker unwinds.
        Self.retainedManagers.append(manager)
        return (manager, isolated.defaults)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
