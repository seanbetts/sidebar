import Foundation
import OSLog

/// Privacy-safe diagnostic event emitted for native intelligence execution.
public struct IntelligenceDiagnosticEvent: Sendable, Equatable, CustomDebugStringConvertible {
    /// Stable event name used by diagnostic recorders.
    public let name: String

    /// Sanitized route metadata associated with the event.
    public let metadata: IntelligenceRouteMetadata

    /// Creates a diagnostic event with sanitized route metadata.
    public init(name: String, metadata: IntelligenceRouteMetadata) {
        self.name = name
        self.metadata = Self.sanitizedMetadata(metadata)
    }

    /// Debug output limited to safe routing fields.
    public var debugDescription: String {
        let capability = metadata.descriptor.capability.rawValue
        let route = metadata.descriptor.executionRoute.rawValue
        let failure = metadata.failureCategory?.rawValue ?? "none"

        return [
            "IntelligenceDiagnosticEvent(name: \(name)",
            "capability: \(capability)",
            "route: \(route)",
            "failure: \(failure))"
        ].joined(separator: ", ")
    }

    private static func sanitizedMetadata(_ metadata: IntelligenceRouteMetadata) -> IntelligenceRouteMetadata {
        IntelligenceRouteMetadata(
            descriptor: metadata.descriptor,
            latencyMs: metadata.latencyMs,
            structuredOutputValid: metadata.structuredOutputValid,
            failureCategory: metadata.failureCategory,
            contextBudget: metadata.contextBudget,
            extra: metadata.extra
        )
    }
}

/// Diagnostic record produced by intelligence services before recorder-specific output.
public enum IntelligenceDiagnosticRecord: Sendable, Equatable {
    /// A model request completed and produced route metadata.
    case modelCompleted(IntelligenceRouteMetadata)

    /// A model request failed before producing complete route metadata.
    case modelFailed(
        descriptor: IntelligenceRouteDescriptor,
        category: IntelligenceFailureCategory,
        latencyMs: Int?
    )

    /// Converts the record into a sanitized diagnostic event.
    public var event: IntelligenceDiagnosticEvent {
        switch self {
        case .modelCompleted(let metadata):
            return IntelligenceDiagnosticEvent(name: "model_completed", metadata: metadata)
        case .modelFailed(let descriptor, let category, let latencyMs):
            return IntelligenceDiagnosticEvent(
                name: "model_failed",
                metadata: IntelligenceRouteMetadata(
                    descriptor: descriptor,
                    latencyMs: latencyMs,
                    structuredOutputValid: false,
                    failureCategory: category,
                    contextBudget: nil
                )
            )
        }
    }
}

/// Records privacy-safe intelligence diagnostics.
public protocol IntelligenceDiagnosticsRecording: Sendable {
    /// Records a single diagnostic record.
    func record(_ record: IntelligenceDiagnosticRecord)
}

/// Test recorder that captures sanitized diagnostic events in memory.
public final class CapturingIntelligenceDiagnosticsRecorder: IntelligenceDiagnosticsRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedEvents: [IntelligenceDiagnosticEvent] = []

    /// Snapshot of captured diagnostic events.
    public var events: [IntelligenceDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return capturedEvents
    }

    /// Creates an empty capturing diagnostics recorder.
    public init() {}

    /// Captures a sanitized diagnostic event.
    public func record(_ record: IntelligenceDiagnosticRecord) {
        let event = record.event
        lock.lock()
        defer { lock.unlock() }
        capturedEvents.append(event)
    }
}

/// OSLog-backed recorder for privacy-safe intelligence diagnostics.
public struct OSLogIntelligenceDiagnosticsRecorder: IntelligenceDiagnosticsRecording {
    private let logger = Logger(subsystem: "sideBar", category: "Intelligence")

    /// Creates an OSLog-backed diagnostics recorder.
    public init() {}

    /// Logs only public routing fields, never prompts, transcripts, payloads, or metadata extras.
    public func record(_ record: IntelligenceDiagnosticRecord) {
        let event = record.event
        let capability = event.metadata.descriptor.capability.rawValue
        let route = event.metadata.descriptor.executionRoute.rawValue
        let failure = event.metadata.failureCategory?.rawValue ?? "none"

        logger.info(
            """
            \(event.name, privacy: .public) \
            capability=\(capability, privacy: .public) \
            route=\(route, privacy: .public) \
            failure=\(failure, privacy: .public)
            """
        )
    }
}
