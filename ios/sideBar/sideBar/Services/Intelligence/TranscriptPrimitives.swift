import Foundation

/// Supported source categories for native speech transcription requests.
public enum AudioSourceKind: String, Codable, Sendable, Equatable {
    case microphone
    case audioFile
    case videoAsset
}

/// Framework-neutral descriptor for an audio source.
public struct AudioSourceDescriptor: Codable, Sendable, Equatable {
    public let kind: AudioSourceKind
    public let identifier: String?

    public init(kind: AudioSourceKind, identifier: String? = nil) {
        self.kind = kind
        self.identifier = identifier
    }
}

/// Optional time range for a transcript event or segment.
public struct TranscriptRange: Codable, Sendable, Equatable {
    public let startTime: TimeInterval?
    public let endTime: TimeInterval?

    public init(startTime: TimeInterval?, endTime: TimeInterval?) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Stable transcript segment model that can be revised while preserving identity.
public struct TranscriptSegment: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let revision: Int
    public let text: String
    public let startTime: TimeInterval?
    public let endTime: TimeInterval?
    public let isFinal: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        revision: Int = 0,
        text: String,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        isFinal: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.revision = revision
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Returns a revised segment with stable identity, range, and creation date.
    public func revised(text: String, isFinal: Bool, updatedAt: Date = Date()) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            revision: revision + 1,
            text: text,
            startTime: startTime,
            endTime: endTime,
            isFinal: isFinal,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Time range covered by this transcript segment.
    public var range: TranscriptRange {
        TranscriptRange(startTime: startTime, endTime: endTime)
    }
}

/// Streamed transcription event emitted by native speech transcription sessions.
public enum TranscriptionEvent: Sendable, Equatable {
    case volatileText(String, TranscriptRange)
    case segmentFinalized(TranscriptSegment)
    case segmentRevised(TranscriptSegment)
    case permissionDenied
    case interrupted
    case cancelled
    case failed(String)
    case completed
}
