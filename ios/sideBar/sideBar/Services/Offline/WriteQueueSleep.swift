import Foundation

typealias WriteQueueSleep = @Sendable (UInt64) async throws -> Void

enum WriteQueueSleepFactory {
    static let live: WriteQueueSleep = { nanoseconds in
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
