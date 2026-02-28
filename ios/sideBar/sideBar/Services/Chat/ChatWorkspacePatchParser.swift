import Foundation
import sideBarShared

enum ChatWorkspacePatchParseResult: Equatable {
    case accepted(actions: [WorkspaceAction], ignoredOperations: Int)
    case rejected(reason: String)
}

enum ChatWorkspacePatchParser {
    static let supportedVersion = 1

    static func parse(data: AnyCodable?) -> ChatWorkspacePatchParseResult {
        guard let payload = data?.value as? [String: Any] else {
            return .rejected(reason: "Missing workspace patch payload.")
        }

        guard let version = intValue(payload["version"]) else {
            return .rejected(reason: "Workspace patch payload is missing version.")
        }

        guard version == supportedVersion else {
            return .rejected(
                reason: "Unsupported workspace patch version \(version)."
            )
        }

        guard let rawOperations = payload["operations"] as? [Any] else {
            return .rejected(
                reason: "Workspace patch payload is missing operations."
            )
        }

        var actions: [WorkspaceAction] = []
        var ignoredOperations = 0

        for rawOperation in rawOperations {
            guard let operation = rawOperation as? [String: Any] else {
                ignoredOperations += 1
                continue
            }
            guard let action = parseOperation(operation) else {
                ignoredOperations += 1
                continue
            }
            actions.append(action)
        }

        return .accepted(actions: actions, ignoredOperations: ignoredOperations)
    }

    private static func parseOperation(_ operation: [String: Any]) -> WorkspaceAction? {
        let opName = firstString(
            in: operation,
            keys: ["op", "type", "action"]
        )

        switch opName {
        case "upsert_agent_surface", "present_agent_surface", "update_agent_surface":
            return parseSurfaceMutationOperation(operation)

        case "close_pane":
            return parseClosePaneOperation(operation)

        case "set_surface_pinned":
            return parseSetSurfacePinnedOperation(operation)

        case "swap_panes":
            return .swapPanes

        default:
            return nil
        }
    }

    private static func parseSurfaceMutationOperation(
        _ operation: [String: Any]
    ) -> WorkspaceAction? {
        guard let pane = paneValue(from: operation, keys: ["pane"]) else {
            return nil
        }
        guard let rawSurface = dictionaryValue(from: operation, keys: ["surface"]) else {
            return nil
        }
        guard let surface = surfaceDescriptor(from: rawSurface) else {
            return nil
        }
        return .presentAgentSurface(surface, pane: pane)
    }

    private static func parseClosePaneOperation(
        _ operation: [String: Any]
    ) -> WorkspaceAction? {
        guard let pane = paneValue(from: operation, keys: ["pane"]) else {
            return nil
        }
        return .closePane(pane)
    }

    private static func parseSetSurfacePinnedOperation(
        _ operation: [String: Any]
    ) -> WorkspaceAction? {
        guard let surfaceId = firstString(
            in: operation,
            keys: ["surface_id", "surfaceId"]
        ) else {
            return nil
        }
        guard let isPinned = firstBool(
            in: operation,
            keys: ["is_pinned", "isPinned"]
        ) else {
            return nil
        }
        return .setAgentSurfacePinned(surfaceId: surfaceId, isPinned: isPinned)
    }

    private static func surfaceDescriptor(
        from rawSurface: [String: Any]
    ) -> AgentWorkspaceSurfaceDescriptor? {
        guard let type = firstString(in: rawSurface, keys: ["type"]) else {
            return nil
        }
        guard let surfaceId = firstString(
            in: rawSurface,
            keys: ["surface_id", "surfaceId"]
        ) else {
            return nil
        }

        var capabilities = AgentWorkspaceSurfaceCapabilities()
        if let rawCapabilities = dictionaryValue(
            from: rawSurface,
            keys: ["capabilities"]
        ) {
            if let canRefresh = firstBool(
                in: rawCapabilities,
                keys: ["can_refresh", "canRefresh"]
            ) {
                capabilities.canRefresh = canRefresh
            }
            if let canClose = firstBool(
                in: rawCapabilities,
                keys: ["can_close", "canClose"]
            ) {
                capabilities.canClose = canClose
            }
            if let canPin = firstBool(
                in: rawCapabilities,
                keys: ["can_pin", "canPin"]
            ) {
                capabilities.canPin = canPin
            }
            if let canInspectData = firstBool(
                in: rawCapabilities,
                keys: ["can_inspect_data", "canInspectData"]
            ) {
                capabilities.canInspectData = canInspectData
            }
        }

        let title = firstString(in: rawSurface, keys: ["title"])
        let isPinned = firstBool(
            in: rawSurface,
            keys: ["is_pinned", "isPinned"]
        ) ?? false
        let payload = payloadStrings(
            from: dictionaryValue(from: rawSurface, keys: ["payload"]) ?? [:]
        )

        return AgentWorkspaceSurfaceDescriptor(
            type: type,
            surfaceId: surfaceId,
            title: title,
            payload: payload,
            capabilities: capabilities,
            isPinned: isPinned
        )
    }

    private static func payloadStrings(
        from payload: [String: Any]
    ) -> [String: String] {
        var values: [String: String] = [:]
        for (key, rawValue) in payload {
            if let value = stringValue(from: rawValue) {
                values[key] = value
            }
        }
        return values
    }

    private static func stringValue(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return String(double)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                  withJSONObject: value,
                  options: [.sortedKeys]
              ),
              let serialized = String(data: data, encoding: .utf8) else {
            return nil
        }
        return serialized
    }

    private static func paneValue(
        from payload: [String: Any],
        keys: [String]
    ) -> WorkspacePane? {
        guard let paneRaw = firstString(in: payload, keys: keys) else {
            return nil
        }
        return WorkspacePane(rawValue: paneRaw)
    }

    private static func dictionaryValue(
        from payload: [String: Any],
        keys: [String]
    ) -> [String: Any]? {
        for key in keys {
            guard let raw = payload[key] else {
                continue
            }
            if let dictionary = raw as? [String: Any] {
                return dictionary
            }
        }
        return nil
    }

    private static func firstString(
        in payload: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let raw = payload[key] as? String else {
                continue
            }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstBool(
        in payload: [String: Any],
        keys: [String]
    ) -> Bool? {
        for key in keys {
            if let bool = payload[key] as? Bool {
                return bool
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }
}
