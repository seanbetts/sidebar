import Foundation
import XCTest
@testable import sideBarShared

final class ExtensionEventStoreTests: XCTestCase {
    func testConcurrentAppendsDropOneEventDuringReadModifyWriteRace() {
        let defaults = RacingUserDefaults()
        let store = ExtensionEventStore(userDefaults: defaults)
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "ExtensionEventStoreTests",
            qos: .userInitiated,
            attributes: .concurrent
        )

        group.enter()
        queue.async {
            store.recordFileSaved(fileId: "file-1", filename: "first.txt")
            group.leave()
        }

        group.enter()
        queue.async {
            store.recordFileSaved(fileId: "file-2", filename: "second.txt")
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)

        let events = store.consumeEvents()
        XCTAssertEqual(events.count, 1)
    }
}

private final class RacingUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String: Any] = [:]
    private var appendReadCount = 0
    private let bothReadsReached = DispatchSemaphore(value: 0)
    private let allowReadsToReturn = DispatchSemaphore(value: 0)

    override func data(forKey defaultName: String) -> Data? {
        let shouldCoordinateRead: Bool
        lock.lock()
        shouldCoordinateRead = defaultName == "extensionEvents" && appendReadCount < 2
        if shouldCoordinateRead {
            appendReadCount += 1
        }
        let value = storedValues[defaultName] as? Data
        lock.unlock()

        guard shouldCoordinateRead else {
            return value
        }

        bothReadsReached.signal()
        _ = allowReadsToReturn.wait(timeout: .now() + 1)
        if appendReadCount == 2 {
            allowReadsToReturn.signal()
        } else {
            _ = bothReadsReached.wait(timeout: .now() + 1)
            allowReadsToReturn.signal()
        }
        return value
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        storedValues[defaultName] = value
        lock.unlock()
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock()
        storedValues.removeValue(forKey: defaultName)
        lock.unlock()
    }

    override func synchronize() -> Bool {
        true
    }
}
