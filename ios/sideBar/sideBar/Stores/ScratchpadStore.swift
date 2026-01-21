import Foundation
import Combine

public nonisolated final class ScratchpadStore: ObservableObject {
    @MainActor @Published public private(set) var version: Int = 0

    public init() {
    }

    @MainActor
    public func bump() {
        version += 1
    }
}
