import Foundation
import Combine

// MARK: - ScratchpadStore

/// Lightweight store for scratchpad version tracking.
///
/// Provides a simple version counter that increments when scratchpad content changes,
/// allowing dependent views to react to updates without holding the full content.
public nonisolated final class ScratchpadStore: ObservableObject {
    @MainActor @Published public private(set) var version: Int = 0

    public init() {
    }

    @MainActor
    public func bump() {
        version += 1
    }
}
