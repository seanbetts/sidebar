import Foundation

/// Reads and writes widget snapshots and pending operations in shared app-group storage.
public final class WidgetDataBridge {
    private let userDefaultsProvider: () -> UserDefaults?
    private let appGroupResolutionProvider: () -> WidgetBridgeAppGroupResolution
    private let diagnosticsRecorder: (String, String, [String: String]) -> Void
    private let timelineReloader: (WidgetContentType) -> Void
    private let pendingOperationStore: WidgetPendingOperationStore

    /// Creates a bridge with explicit storage, diagnostics, timeline, and pending-operation dependencies.
    public init(
        userDefaultsProvider: @escaping () -> UserDefaults?,
        appGroupResolutionProvider: @escaping () -> WidgetBridgeAppGroupResolution,
        diagnosticsRecorder: @escaping (String, String, [String: String]) -> Void,
        timelineReloader: @escaping (WidgetContentType) -> Void,
        pendingOperationStore: WidgetPendingOperationStore? = nil
    ) {
        self.userDefaultsProvider = userDefaultsProvider
        self.appGroupResolutionProvider = appGroupResolutionProvider
        self.diagnosticsRecorder = diagnosticsRecorder
        self.timelineReloader = timelineReloader
        self.pendingOperationStore = pendingOperationStore ?? WidgetPendingOperationStore(
            userDefaultsProvider: userDefaultsProvider,
            appGroupResolutionProvider: appGroupResolutionProvider
        )
    }

    /// Loads the stored widget snapshot for a content type or returns the container's empty value.
    public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
        let resolution = appGroupResolutionProvider()
        guard let defaults = userDefaultsProvider() else {
            diagnosticsRecorder(
                "load_empty",
                "No widget data snapshot was available.",
                [
                    "content_type": contentType.rawValue,
                    "app_group_source": resolution.source,
                    "has_defaults": "false",
                    "has_data_key": "false"
                ]
            )
            return T.empty
        }

        guard let data = defaults.data(forKey: contentType.dataKey) else {
            diagnosticsRecorder(
                "load_empty",
                "No widget data snapshot was available.",
                [
                    "content_type": contentType.rawValue,
                    "app_group_source": resolution.source,
                    "has_defaults": "true",
                    "has_data_key": defaults.object(forKey: contentType.dataKey) == nil ? "false" : "true"
                ]
            )
            return T.empty
        }

        let decoded = try? Self.makeDecoder().decode(T.self, from: data)
        diagnosticsRecorder(
            "load",
            "Loaded widget data snapshot.",
            [
                "content_type": contentType.rawValue,
                "app_group_source": resolution.source,
                "has_defaults": "true",
                "has_data_key": "true",
                "bytes": "\(data.count)",
                "decode_success": decoded == nil ? "false" : "true",
                "item_count": "\(decoded?.items.count ?? 0)",
                "total_count": "\(decoded?.totalCount ?? 0)"
            ]
        )
        return decoded ?? T.empty
    }

    /// Returns whether a snapshot key exists for a content type.
    public func hasStoredSnapshot(for contentType: WidgetContentType) -> Bool {
        guard let defaults = userDefaultsProvider() else { return false }
        return defaults.object(forKey: contentType.dataKey) != nil
    }

    /// Stores a widget snapshot and asks WidgetKit to reload matching timelines.
    public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
        let resolution = appGroupResolutionProvider()
        guard let defaults = userDefaultsProvider() else {
            diagnosticsRecorder(
                "store_missing_defaults",
                "Could not store widget data snapshot because shared defaults were unavailable.",
                [
                    "content_type": contentType.rawValue,
                    "app_group_source": resolution.source,
                    "has_defaults": "false"
                ]
            )
            return
        }

        if let encoded = try? Self.makeEncoder().encode(data) {
            defaults.set(encoded, forKey: contentType.dataKey)
            diagnosticsRecorder(
                "store",
                "Stored widget data snapshot.",
                [
                    "content_type": contentType.rawValue,
                    "app_group_source": resolution.source,
                    "has_defaults": "true",
                    "bytes": "\(encoded.count)",
                    "item_count": "\(data.items.count)",
                    "total_count": "\(data.totalCount)"
                ]
            )
        }

        timelineReloader(contentType)
    }

    /// Records a pending widget operation for later app-side reconciliation.
    public func recordPendingOperation<A: Codable & Equatable>(
        _ operation: WidgetPendingOperation<A>,
        for contentType: WidgetContentType
    ) {
        guard let count = pendingOperationStore.record(operation, key: contentType.pendingKey) else {
            return
        }

        diagnosticsRecorder(
            "record_pending_operation",
            "Recorded widget pending operation.",
            [
                "content_type": contentType.rawValue,
                "count": "\(count)"
            ]
        )
    }

    /// Consumes all pending operations for a widget content type.
    public func consumePendingOperations<A: Codable & Equatable>(
        for contentType: WidgetContentType,
        actionType: A.Type
    ) -> [WidgetPendingOperation<A>] {
        guard let pending = pendingOperationStore.consume(
            key: contentType.pendingKey,
            actionType: actionType
        ) else {
            return []
        }

        diagnosticsRecorder(
            "consume_pending_operations",
            "Consumed widget pending operations.",
            [
                "content_type": contentType.rawValue,
                "count": "\(pending.count)"
            ]
        )
        return pending
    }

    /// Consumes pending operations that match a predicate and keeps nonmatching operations stored.
    public func consumePendingOperations<A: Codable & Equatable>(
        for contentType: WidgetContentType,
        actionType: A.Type,
        matching: (A) -> Bool
    ) -> [WidgetPendingOperation<A>] {
        guard let result = pendingOperationStore.consume(
            key: contentType.pendingKey,
            actionType: actionType,
            matching: matching
        ) else {
            return []
        }

        diagnosticsRecorder(
            "consume_matching_pending_operations",
            "Consumed matching widget pending operations.",
            [
                "content_type": contentType.rawValue,
                "matched_count": "\(result.matched.count)",
                "remaining_count": "\(result.remainingCount)"
            ]
        )
        return result.matched
    }

    /// Loads pending operations without removing them from shared storage.
    public func loadPendingOperations<A: Codable & Equatable>(
        for contentType: WidgetContentType,
        actionType: A.Type
    ) -> [WidgetPendingOperation<A>] {
        pendingOperationStore.load(key: contentType.pendingKey, actionType: actionType)
    }

    /// Removes one pending operation by identifier.
    public func removePendingOperation<A: Codable & Equatable>(
        withId operationId: String,
        for contentType: WidgetContentType,
        actionType: A.Type
    ) {
        guard let remainingCount = pendingOperationStore.remove(
            id: operationId,
            key: contentType.pendingKey,
            actionType: actionType
        ) else {
            return
        }

        diagnosticsRecorder(
            "remove_pending_operation",
            "Removed widget pending operation.",
            [
                "content_type": contentType.rawValue,
                "removed_operation_id": operationId,
                "remaining_count": "\(remainingCount)"
            ]
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
