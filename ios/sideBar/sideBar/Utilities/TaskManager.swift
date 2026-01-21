import Foundation

/// Manages a single cancellable task.
@MainActor
public final class ManagedTask {
    private var task: Task<Void, Never>?

    public init() {
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Starts a new task, canceling any existing one.
    public func run(_ action: @escaping @MainActor () async -> Void) {
        cancel()
        task = Task { await action() }
    }

    /// Starts a new task after delay (useful for debouncing).
    public func runDebounced(
        delay: TimeInterval,
        _ action: @escaping @MainActor () async -> Void
    ) {
        cancel()
        task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

/// Manages a repeating polling task.
public final class PollingTask {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public func start(_ action: @escaping @Sendable () async -> Void) {
        cancel()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
