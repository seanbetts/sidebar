import Foundation
import OSLog
import Realtime
import Supabase

// MARK: - SupabaseRealtimeAdapter

public protocol RealtimeEventHandler: AnyObject {
    func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>)
    func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>)
    func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>)
    func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>)
}

/// Bridges Supabase realtime events into app payloads.
public final class SupabaseRealtimeAdapter: RealtimeClient {
    public weak var handler: RealtimeEventHandler?
    private let tokenStore: AccessTokenStore
    private let client: SupabaseClient
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "sideBar", category: "Realtime")
    private var currentUserId: String?
    private var notesChannel: RealtimeChannelV2?
    private var websitesChannel: RealtimeChannelV2?
    private var ingestedFilesChannel: RealtimeChannelV2?
    private var fileJobsChannel: RealtimeChannelV2?
    private var notesSubscriptions: [ObservationToken] = []
    private var websitesSubscriptions: [ObservationToken] = []
    private var ingestedFilesSubscriptions: [ObservationToken] = []
    private var fileJobsSubscriptions: [ObservationToken] = []

    public init(config: EnvironmentConfig, handler: RealtimeEventHandler? = nil) {
        self.handler = handler
        self.tokenStore = AccessTokenStore()
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
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
        await tokenStore.set(accessToken)
        await client.realtimeV2.setAuth(accessToken)
        let shouldResubscribeNotes = currentUserId != userId || notesChannel == nil
        let shouldResubscribeWebsites = currentUserId != userId || websitesChannel == nil
        let shouldResubscribeIngestedFiles = currentUserId != userId || ingestedFilesChannel == nil
        let shouldResubscribeFileJobs = currentUserId != userId || fileJobsChannel == nil
        currentUserId = userId
        if shouldResubscribeNotes {
            await subscribeToNotes(userId: userId)
        }
        if shouldResubscribeWebsites {
            await subscribeToWebsites(userId: userId)
        }
        if shouldResubscribeIngestedFiles {
            await subscribeToIngestedFiles(userId: userId)
        }
        if shouldResubscribeFileJobs {
            await subscribeToFileJobs()
        }
    }

    public func stop() {
        notesSubscriptions.removeAll()
        websitesSubscriptions.removeAll()
        ingestedFilesSubscriptions.removeAll()
        fileJobsSubscriptions.removeAll()
        let channel = notesChannel
        let websitesChannel = websitesChannel
        let ingestedFilesChannel = ingestedFilesChannel
        let fileJobsChannel = fileJobsChannel
        notesChannel = nil
        self.websitesChannel = nil
        self.ingestedFilesChannel = nil
        self.fileJobsChannel = nil
        Task {
            await tokenStore.set(nil)
        }
        currentUserId = nil
        if let channel {
            Task {
                await client.realtimeV2.removeChannel(channel)
            }
        }
        if let websitesChannel {
            Task {
                await client.realtimeV2.removeChannel(websitesChannel)
            }
        }
        if let ingestedFilesChannel {
            Task {
                await client.realtimeV2.removeChannel(ingestedFilesChannel)
            }
        }
        if let fileJobsChannel {
            Task {
                await client.realtimeV2.removeChannel(fileJobsChannel)
            }
        }
    }

    private func subscribeToNotes(userId: String) async {
        if let existingChannel = notesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        notesSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.notes)")
        let filter = "user_id=eq.\(userId)"
        notesSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        notesSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        notesSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        notesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch {
            logger.error("Notes subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribeToWebsites(userId: String) async {
        if let existingChannel = websitesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        websitesSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.websites)")
        let filter = "user_id=eq.\(userId)"
        websitesSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.websites,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleWebsiteInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        websitesSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.websites,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleWebsiteUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        websitesSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.websites,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleWebsiteDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        websitesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch {
            logger.error("Websites subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribeToIngestedFiles(userId: String) async {
        if let existingChannel = ingestedFilesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        ingestedFilesSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.ingestedFiles)")
        let filter = "user_id=eq.\(userId)"
        ingestedFilesSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.ingestedFiles,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleIngestedFileInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        ingestedFilesSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.ingestedFiles,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleIngestedFileUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        ingestedFilesSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.ingestedFiles,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleIngestedFileDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        ingestedFilesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch {
            logger.error("Ingested files subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribeToFileJobs() async {
        if let existingChannel = fileJobsChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        fileJobsSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.fileJobs)")
        fileJobsSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.fileJobs
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleFileJobInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        fileJobsSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.fileJobs
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleFileJobUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        fileJobsSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.fileJobs
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleFileJobDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        fileJobsChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch {
            logger.error("File jobs subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleNoteInsert(_ action: RealtimeActionDecoding) {
        do {
            let record: NoteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyNoteEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Notes insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleNoteUpdate(_ action: RealtimeActionDecoding) {
        do {
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
        Task { @MainActor [weak self] in
            self?.handler?.handleNoteEvent(payload)
        }
    }

    func handleWebsiteInsert(_ action: RealtimeActionDecoding) {
        do {
            let record: WebsiteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyWebsiteEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Websites insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleWebsiteUpdate(_ action: RealtimeActionDecoding) {
        do {
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
            let oldRecord: WebsiteRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyWebsiteEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Websites delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleIngestedFileInsert(_ action: RealtimeActionDecoding) {
        do {
            let record: IngestedFileRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyIngestedFileEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Ingested files insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleIngestedFileUpdate(_ action: RealtimeActionDecoding) {
        do {
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
            let oldRecord: IngestedFileRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyIngestedFileEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Ingested files delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFileJobInsert(_ action: RealtimeActionDecoding) {
        do {
            let record: FileJobRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyFileJobEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("File jobs insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFileJobUpdate(_ action: RealtimeActionDecoding) {
        do {
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
            let oldRecord: FileJobRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyFileJobEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("File jobs delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
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
        Task { @MainActor [weak self] in
            self?.handler?.handleWebsiteEvent(payload)
        }
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
        Task { @MainActor [weak self] in
            self?.handler?.handleIngestedFileEvent(payload)
        }
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
        Task { @MainActor [weak self] in
            self?.handler?.handleFileJobEvent(payload)
        }
    }
}

private actor AccessTokenStore {
    private var token: String?

    func get() -> String? {
        token
    }

    func set(_ token: String?) {
        self.token = token
    }
}

public struct NoteRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let content: String?
    public let metadata: [String: AnyCodable]?
    public let updatedAt: String?
    public let deletedAt: String?
}

public struct WebsiteRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let url: String?
    public let domain: String?
    public let metadata: [String: AnyCodable]?
    public let savedAt: String?
    public let publishedAt: String?
    public let updatedAt: String?
    public let lastOpenedAt: String?
    public let deletedAt: String?
}

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

public struct FileJobRealtimeRecord: Codable {
    public let fileId: String
    public let status: String?
    public let stage: String?
    public let errorCode: String?
    public let errorMessage: String?
    public let attempts: Int?
    public let updatedAt: String?
}
