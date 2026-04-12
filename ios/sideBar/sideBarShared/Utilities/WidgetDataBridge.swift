import Foundation

public final class WidgetDataBridge {
    private let userDefaultsProvider: () -> UserDefaults?
    private let appGroupResolutionProvider: () -> WidgetBridgeAppGroupResolution
    private let diagnosticsRecorder: (String, String, [String: String]) -> Void
    private let timelineReloader: (WidgetContentType) -> Void

    public init(
        userDefaultsProvider: @escaping () -> UserDefaults?,
        appGroupResolutionProvider: @escaping () -> WidgetBridgeAppGroupResolution,
        diagnosticsRecorder: @escaping (String, String, [String: String]) -> Void,
        timelineReloader: @escaping (WidgetContentType) -> Void
    ) {
        self.userDefaultsProvider = userDefaultsProvider
        self.appGroupResolutionProvider = appGroupResolutionProvider
        self.diagnosticsRecorder = diagnosticsRecorder
        self.timelineReloader = timelineReloader
    }

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

    public func hasStoredSnapshot(for contentType: WidgetContentType) -> Bool {
        guard let defaults = userDefaultsProvider() else { return false }
        return defaults.object(forKey: contentType.dataKey) != nil
    }

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

    public func recordPendingOperation<A: Codable & Equatable>(
        _ operation: WidgetPendingOperation<A>,
        for contentType: WidgetContentType
    ) {
        guard let defaults = userDefaultsProvider() else { return }
        var pending = loadPendingOperations(for: contentType, actionType: A.self)
        if !pending.contains(where: { $0.itemId == operation.itemId && $0.action == operation.action }) {
            pending.append(operation)
            if let encoded = try? Self.makeEncoder().encode(pending) {
                defaults.set(encoded, forKey: contentType.pendingKey)
                diagnosticsRecorder(
                    "record_pending_operation",
                    "Recorded widget pending operation.",
                    [
                        "content_type": contentType.rawValue,
                        "count": "\(pending.count)"
                    ]
                )
            }
        }
    }

    public func consumePendingOperations<A: Codable & Equatable>(
        for contentType: WidgetContentType,
        actionType: A.Type
    ) -> [WidgetPendingOperation<A>] {
        guard let defaults = userDefaultsProvider() else { return [] }
        let pending = loadPendingOperations(for: contentType, actionType: actionType)
        defaults.removeObject(forKey: contentType.pendingKey)
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

    public func consumePendingOperations<A: Codable & Equatable>(
        for contentType: WidgetContentType,
        actionType: A.Type,
        matching: (A) -> Bool
    ) -> [WidgetPendingOperation<A>] {
        guard let defaults = userDefaultsProvider() else { return [] }
        let pending = loadPendingOperations(for: contentType, actionType: actionType)
        guard !pending.isEmpty else { return [] }

        let matchingOperations = pending.filter { matching($0.action) }
        let remainingOperations = pending.filter { !matching($0.action) }

        if remainingOperations.isEmpty {
            defaults.removeObject(forKey: contentType.pendingKey)
        } else if let encoded = try? Self.makeEncoder().encode(remainingOperations) {
            defaults.set(encoded, forKey: contentType.pendingKey)
        }
        diagnosticsRecorder(
            "consume_matching_pending_operations",
            "Consumed matching widget pending operations.",
            [
                "content_type": contentType.rawValue,
                "matched_count": "\(matchingOperations.count)",
                "remaining_count": "\(remainingOperations.count)"
            ]
        )
        return matchingOperations
    }

    public func loadPendingOperations<A: Codable & Equatable>(
        for contentType: WidgetContentType,
        actionType: A.Type
    ) -> [WidgetPendingOperation<A>] {
        guard let defaults = userDefaultsProvider(),
              let data = defaults.data(forKey: contentType.pendingKey) else {
            return []
        }
        return (try? Self.makeDecoder().decode([WidgetPendingOperation<A>].self, from: data)) ?? []
    }

    public func removePendingOperation<A: Codable & Equatable>(
        withId operationId: String,
        for contentType: WidgetContentType,
        actionType: A.Type
    ) {
        guard let defaults = userDefaultsProvider() else { return }
        let pending = loadPendingOperations(for: contentType, actionType: actionType)
        guard !pending.isEmpty else { return }

        let filtered = pending.filter { $0.id != operationId }
        guard filtered.count != pending.count else { return }

        if filtered.isEmpty {
            defaults.removeObject(forKey: contentType.pendingKey)
        } else if let encoded = try? Self.makeEncoder().encode(filtered) {
            defaults.set(encoded, forKey: contentType.pendingKey)
        }
        diagnosticsRecorder(
            "remove_pending_operation",
            "Removed widget pending operation.",
            [
                "content_type": contentType.rawValue,
                "removed_operation_id": operationId,
                "remaining_count": "\(filtered.count)"
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
