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

        case "open_entity":
            return parseOpenEntityOperation(operation)

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

    private static func parseOpenEntityOperation(
        _ operation: [String: Any]
    ) -> WorkspaceAction? {
        guard let rawEntity = dictionaryValue(from: operation, keys: ["entity"]),
              let entityType = firstString(
                  in: rawEntity,
                  keys: ["type", "entity_type", "entityType"]
              ),
              let entityId = firstString(
                  in: rawEntity,
                  keys: ["id", "entity_id", "entityId"]
              ) else {
            return nil
        }

        let routeURL = firstString(
            in: operation,
            keys: ["route_url", "routeURL", "url"]
        ).flatMap(URL.init(string:))
        let section = firstString(
            in: operation,
            keys: ["section"]
        ).flatMap(AppSection.init(rawValue:))
        let pane = paneValue(from: operation, keys: ["pane"]) ?? .primary
        let entity = WorkspaceEntityReference(
            type: entityType,
            id: entityId,
            title: firstString(in: rawEntity, keys: ["title", "name"]),
            path: firstString(in: rawEntity, keys: ["path", "file_path", "filePath"])
        )

        return .openEntity(
            WorkspaceEntityOpenRequest(
                entity: entity,
                routeURL: routeURL,
                section: section,
                pane: pane
            )
        )
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

        let title = firstString(in: rawSurface, keys: ["title"])
        let capabilities = capabilities(from: rawSurface)
        let isPinned = firstBool(
            in: rawSurface,
            keys: ["is_pinned", "isPinned"]
        ) ?? false
        let surfaceClass = AgentWorkspaceSurfaceClass(
            rawValue: firstString(
                in: rawSurface,
                keys: ["surface_class", "surfaceClass"]
            ) ?? ""
        ) ?? .display
        let authorityMode = AgentWorkspaceAuthorityMode(
            rawValue: firstString(
                in: rawSurface,
                keys: ["authority_mode", "authorityMode"]
            ) ?? ""
        ) ?? .readOnly
        let boundEntity = boundEntityReference(
            from: rawSurface,
            keys: ["bound_entity", "boundEntity"]
        )
        let collaborationScope = collaborationScope(
            from: rawSurface,
            keys: ["collaboration_scope", "collaborationScope"]
        )
        let payload = payloadStrings(
            from: dictionaryValue(from: rawSurface, keys: ["payload"]) ?? [:]
        )
        let contextMenuActions = contextMenuActions(from: rawSurface)

        return AgentWorkspaceSurfaceDescriptor(
            type: type,
            surfaceId: surfaceId,
            title: title,
            payload: payload,
            contextMenuActions: contextMenuActions,
            surfaceClass: surfaceClass,
            authorityMode: authorityMode,
            boundEntity: boundEntity,
            collaborationScope: collaborationScope,
            capabilities: capabilities,
            isPinned: isPinned
        )
    }

    private static func capabilities(
        from rawSurface: [String: Any]
    ) -> AgentWorkspaceSurfaceCapabilities {
        guard let rawCapabilities = dictionaryValue(
            from: rawSurface,
            keys: ["capabilities"]
        ) else {
            return AgentWorkspaceSurfaceCapabilities()
        }

        var capabilities = AgentWorkspaceSurfaceCapabilities()
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
        return capabilities
    }

    private static func boundEntityReference(
        from payload: [String: Any],
        keys: [String]
    ) -> AgentWorkspaceBoundEntityReference? {
        guard let rawBoundEntity = dictionaryValue(from: payload, keys: keys),
              let entityType = firstString(
                  in: rawBoundEntity,
                  keys: ["type", "entity_type", "entityType"]
              ),
              let entityId = firstString(
                  in: rawBoundEntity,
                  keys: ["id", "entity_id", "entityId"]
              ) else {
            return nil
        }

        return AgentWorkspaceBoundEntityReference(
            entityType: entityType,
            entityId: entityId
        )
    }

    private static func collaborationScope(
        from payload: [String: Any],
        keys: [String]
    ) -> AgentWorkspaceCollaborationScope {
        guard let rawScope = dictionaryValue(from: payload, keys: keys),
              let mode = firstString(in: rawScope, keys: ["mode"]) else {
            return .none
        }

        switch mode {
        case "conversation_bound_entity":
            guard let entityType = firstString(
                in: rawScope,
                keys: ["entity_type", "entityType", "type"]
            ),
            let entityId = firstString(
                in: rawScope,
                keys: ["entity_id", "entityId", "id"]
            ) else {
                return .none
            }
            return .conversationBoundEntity(
                entityType: entityType,
                entityId: entityId
            )

        default:
            return .none
        }
    }

    private static func contextMenuActions(
        from rawSurface: [String: Any]
    ) -> [AgentWorkspaceContextMenuAction] {
        guard let rawActions = firstArray(
            in: rawSurface,
            keys: ["context_menu_actions", "contextMenuActions"]
        ) else {
            return []
        }

        var parsed: [AgentWorkspaceContextMenuAction] = []
        var seen: Set<AgentWorkspaceContextMenuAction> = []
        for rawAction in rawActions {
            guard let name = rawAction as? String,
                  let action = AgentWorkspaceContextMenuAction(
                      rawValue: name.trimmingCharacters(in: .whitespacesAndNewlines)
                  ),
                  !seen.contains(action) else {
                continue
            }
            seen.insert(action)
            parsed.append(action)
        }
        return parsed
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

    private static func firstArray(
        in payload: [String: Any],
        keys: [String]
    ) -> [Any]? {
        for key in keys {
            if let array = payload[key] as? [Any] {
                return array
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
