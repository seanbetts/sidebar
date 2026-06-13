import Foundation

/// Running transcription session that emits events until stopped, cancelled, or completed.
public protocol TranscriptionSession: Sendable {
    var events: AsyncStream<TranscriptionEvent> { get }
    func stop() async
    func cancel() async
}

/// Boundary for speech transcription without exposing Apple framework types to callers.
public protocol SpeechTranscriptionServicing: Sendable {
    func start(source: AudioSourceDescriptor) async throws -> any TranscriptionSession
}

/// Deterministic transcription session for XCTest and injected local workflows.
public final class FakeTranscriptionSession: TranscriptionSession, @unchecked Sendable {
    public let events: AsyncStream<TranscriptionEvent>
    private let continuationStore: TranscriptionContinuationStore

    public init(events configuredEvents: [TranscriptionEvent]) {
        continuationStore = TranscriptionContinuationStore()
        events = AsyncStream { continuation in
            for event in configuredEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    public init() {
        let store = TranscriptionContinuationStore()
        continuationStore = store
        events = AsyncStream { continuation in
            store.set(continuation)
        }
    }

    /// Emits one event for interactive tests.
    public func yield(_ event: TranscriptionEvent) {
        continuationStore.yield(event)
    }

    /// Finishes the event stream for interactive tests.
    public func finish() {
        continuationStore.finish()
    }

    public func stop() async {
        continuationStore.yield(.completed)
        continuationStore.finish()
    }

    public func cancel() async {
        continuationStore.yield(.cancelled)
        continuationStore.finish()
    }
}

/// Deterministic fake speech transcription service that records source descriptors.
public final class FakeSpeechTranscriptionService: SpeechTranscriptionServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSources: [AudioSourceDescriptor] = []
    private var queuedSessions: [any TranscriptionSession]

    public var sources: [AudioSourceDescriptor] {
        lock.withLock {
            recordedSources
        }
    }

    public init(sessions: [any TranscriptionSession] = []) {
        queuedSessions = sessions
    }

    public func enqueue(session: any TranscriptionSession) {
        lock.withLock {
            queuedSessions.append(session)
        }
    }

    public func start(source: AudioSourceDescriptor) async throws -> any TranscriptionSession {
        lock.withLock {
            recordedSources.append(source)
            if queuedSessions.isEmpty {
                return FakeTranscriptionSession(events: [])
            }
            return queuedSessions.removeFirst()
        }
    }
}

private final class TranscriptionContinuationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var isFinished = false

    func set(_ continuation: AsyncStream<TranscriptionEvent>.Continuation) {
        let shouldFinish = lock.withLock {
            if isFinished {
                return true
            }
            self.continuation = continuation
            return false
        }
        if shouldFinish {
            continuation.finish()
        }
    }

    func yield(_ event: TranscriptionEvent) {
        let target = lock.withLock {
            isFinished ? nil : continuation
        }
        target?.yield(event)
    }

    func finish() {
        let target = lock.withLock {
            guard !isFinished else {
                return nil as AsyncStream<TranscriptionEvent>.Continuation?
            }
            isFinished = true
            let target = continuation
            continuation = nil
            return target
        }
        target?.finish()
    }
}
