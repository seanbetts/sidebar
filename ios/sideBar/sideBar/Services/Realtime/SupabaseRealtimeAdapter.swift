import Combine
import Foundation
import sideBarShared
import OSLog
import Supabase

// MARK: - SupabaseRealtimeAdapter

/// Defines the requirements for RealtimeEventHandler.
public protocol RealtimeEventHandler: AnyObject {
    func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>)
    func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>)
    func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>)
    func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>)
    func handleTaskEvent(_ payload: RealtimePayload<TaskRealtimeRecord>)
    func handleTaskProjectEvent(_ payload: RealtimePayload<TaskProjectRealtimeRecord>)
    func handleTaskGroupEvent(_ payload: RealtimePayload<TaskGroupRealtimeRecord>)
}

/// Bridges Supabase realtime events into app payloads.
///
/// All mutable channel and subscription state is accessed on the main actor
/// to prevent data races between `start()` and `stop()`.
@MainActor public final class SupabaseRealtimeAdapter: RealtimeClient {
    public weak var handler: RealtimeEventHandler?
    @Published private(set) var isRealtimeConnected: Bool = false
    let tokenStore: AccessTokenStore
    let client: SupabaseClient
    let logger = Logger(subsystem: "sideBar", category: "Realtime")
    var currentUserId: String?
    var currentAccessToken: String?
    var subscriptionSlots: [RealtimeSubscriptionDomain: RealtimeSubscriptionSlot] = Dictionary(
        uniqueKeysWithValues: RealtimeSubscriptionDomain.allCases.map { ($0, RealtimeSubscriptionSlot()) }
    )
    var transitionTask: Task<Void, Never>?

    public init(config: EnvironmentConfig, handler: RealtimeEventHandler? = nil) {
        self.handler = handler
        self.tokenStore = AccessTokenStore()
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                accessToken: { [tokenStore] in await tokenStore.get() }
            )
        )
        self.client = SupabaseClient(
            supabaseURL: config.supabaseUrl,
            supabaseKey: config.supabaseAnonKey,
            options: options
        )
    }

    public func start(userId: String, accessToken: String?) async {
        let task = enqueueTransition { [weak self] in
            await self?.startInternal(userId: userId, accessToken: accessToken)
        }
        await task.value
    }

    public func stop() {
        _ = enqueueTransition { [weak self] in
            await self?.stopInternal()
        }
    }

    static func shouldResubscribeChannel(
        currentSession: RealtimeSubscriptionSession?,
        nextSession: RealtimeSubscriptionSession,
        hasChannel: Bool
    ) -> Bool {
        !hasChannel || currentSession != nextSession
    }

    func setRealtimeConnected(_ isConnected: Bool) {
        isRealtimeConnected = isConnected
    }

    func updateRealtimeConnectionState() {
        guard let currentSession = RealtimeSubscriptionSession(
            userId: currentUserId,
            accessToken: currentAccessToken
        ) else {
            isRealtimeConnected = false
            return
        }
        isRealtimeConnected = RealtimeSubscriptionDomain.allCases.allSatisfy { domain in
            guard let slot = subscriptionSlots[domain] else { return false }
            return slot.channel != nil && slot.subscribedSession == currentSession
        }
    }
}

extension SupabaseRealtimeAdapter {
    func handleNoteInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: NoteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyNoteEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Notes insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleNoteUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: NoteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: NoteRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("Notes update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyNoteEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("Notes update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleNoteDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: NoteRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyNoteEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Notes delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func notifyNoteEvent(
        type: RealtimeEventType,
        record: NoteRealtimeRecord?,
        oldRecord: NoteRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.notes,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        handler?.handleNoteEvent(payload)
    }

    func handleWebsiteInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: WebsiteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyWebsiteEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Websites insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleWebsiteUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: WebsiteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: WebsiteRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("Websites update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyWebsiteEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("Websites update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleWebsiteDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: WebsiteRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyWebsiteEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Websites delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleIngestedFileInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: IngestedFileRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyIngestedFileEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Ingested files insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleIngestedFileUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: IngestedFileRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: IngestedFileRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("Ingested files update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyIngestedFileEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("Ingested files update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleIngestedFileDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: IngestedFileRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyIngestedFileEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Ingested files delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFileJobInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: FileJobRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyFileJobEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("File jobs insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFileJobUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: FileJobRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: FileJobRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("File jobs update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyFileJobEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("File jobs update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFileJobDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: FileJobRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyFileJobEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("File jobs delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func notifyWebsiteEvent(
        type: RealtimeEventType,
        record: WebsiteRealtimeRecord?,
        oldRecord: WebsiteRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.websites,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        handler?.handleWebsiteEvent(payload)
    }

    private func notifyIngestedFileEvent(
        type: RealtimeEventType,
        record: IngestedFileRealtimeRecord?,
        oldRecord: IngestedFileRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.ingestedFiles,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        handler?.handleIngestedFileEvent(payload)
    }

    private func notifyFileJobEvent(
        type: RealtimeEventType,
        record: FileJobRealtimeRecord?,
        oldRecord: FileJobRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.fileJobs,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        handler?.handleFileJobEvent(payload)
    }
}

actor AccessTokenStore {
    private var token: String?

    func get() -> String? {
        token
    }

    func set(_ token: String?) {
        self.token = token
    }
}

/// Represents NoteRealtimeRecord.
public struct NoteRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let document: NotesSemanticDocument?
    public let documentVersion: Int?
    public let plainText: String?
    public let metadata: [String: AnyCodable]?
    public let updatedAt: String?
    public let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case document
        case documentVersion = "document_version"
        case plainText = "plain_text"
        case metadata
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

/// Represents WebsiteRealtimeRecord.
public struct WebsiteRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let url: String?
    public let domain: String?
    public let metadata: [String: AnyCodable]?
    public let savedAt: String?
    public let publishedAt: String?
    public var readingTime: String?
    public let updatedAt: String?
    public let lastOpenedAt: String?
    public let deletedAt: String?
}

/// Represents IngestedFileRealtimeRecord.
public struct IngestedFileRealtimeRecord: Codable {
    public let id: String
    public let filenameOriginal: String?
    public let path: String?
    public let mimeOriginal: String?
    public let sizeBytes: Int?
    public let sha256: String?
    public let sourceUrl: String?
    public let sourceMetadata: [String: AnyCodable]?
    public let pinned: Bool?
    public let pinnedOrder: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let deletedAt: String?
}

/// Represents FileJobRealtimeRecord.
public struct FileJobRealtimeRecord: Codable {
    public let fileId: String
    public let status: String?
    public let stage: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let attempts: Int?
    public let updatedAt: String?
}
