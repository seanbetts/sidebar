import Foundation
import Realtime
import Supabase

public protocol RealtimeEventHandler: AnyObject {
    func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>)
    func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>)
    func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>)
    func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>)
}

public final class SupabaseRealtimeAdapter: RealtimeClient {
    public weak var handler: RealtimeEventHandler?
    private let tokenStore: AccessTokenStore
    private let client: SupabaseClient
    private let decoder: JSONDecoder
    private var currentUserId: String?
    private var notesChannel: RealtimeChannelV2?
    private var subscriptions: [ObservationToken] = []

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
        let shouldResubscribe = currentUserId != userId || notesChannel == nil
        currentUserId = userId
        if shouldResubscribe {
            await subscribeToNotes(userId: userId)
        }
    }

    public func stop() {
        subscriptions.removeAll()
        let channel = notesChannel
        notesChannel = nil
        Task {
            await tokenStore.set(nil)
        }
        currentUserId = nil
        if let channel {
            Task {
                await client.realtimeV2.removeChannel(channel)
            }
        }
    }

    private func subscribeToNotes(userId: String) async {
        if let existingChannel = notesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        subscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.notes)")
        let filter = "user_id=eq.\(userId)"
        subscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteInsert(action)
                }
            }
        )
        subscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteUpdate(action)
                }
            }
        )
        subscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteDelete(action)
                }
            }
        )
        notesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch {
        }
    }

    private func handleNoteInsert(_ action: InsertAction) {
        do {
            let record: NoteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyNoteEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
        }
    }

    private func handleNoteUpdate(_ action: UpdateAction) {
        do {
            let record: NoteRealtimeRecord = try action.decodeRecord(decoder: decoder)
            let oldRecord: NoteRealtimeRecord? = try? action.decodeOldRecord(decoder: decoder)
            notifyNoteEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
        }
    }

    private func handleNoteDelete(_ action: DeleteAction) {
        do {
            let oldRecord: NoteRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyNoteEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
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
