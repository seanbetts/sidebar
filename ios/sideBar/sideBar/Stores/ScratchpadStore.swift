import Foundation
import Combine

@MainActor
public final class ScratchpadStore: ObservableObject {
    @Published public private(set) var version: Int = 0

    public init() {
    }

    public func bump() {
        version += 1
    }
}
