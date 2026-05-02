import Foundation
import sideBarShared

struct ChatToolDetailSection: Equatable, Identifiable {
    let kind: ChatToolDetailSectionKind
    let title: String
    let subtitle: String?
    let isCollapsible: Bool
    let startsExpanded: Bool

    var id: ChatToolDetailSectionKind { kind }
}

enum ChatToolDetailSectionKind: String, Equatable, Identifiable {
    case summary
    case workspaceActions

    var id: String { rawValue }
}

enum ChatToolPresentation {
    struct Summary: Equatable {
        let primaryText: String
        let secondaryText: String?
        let showsToolList: Bool
    }

    static func displayName(for toolCall: ToolCall) -> String {
        let skillID = toolCall.skillId
            ?? toolCall.iconKey
            ?? SkillIconResolver.skillId(forToolDisplayName: toolCall.name)
        if skillID == "prompt-preview" {
            return "Prompt Preview"
        }
        return toolCall.name
    }

    static func visibleToolCalls(from toolCalls: [ToolCall]) -> [ToolCall] {
        guard toolCalls.count > 1 else {
            return toolCalls
        }

        var hiddenIndices = Set<Int>()
        var runStart = 0

        while runStart < toolCalls.count {
            let family = toolFamily(for: toolCalls[runStart])
            var runEnd = runStart + 1
            while runEnd < toolCalls.count, toolFamily(for: toolCalls[runEnd]) == family {
                runEnd += 1
            }

            var recoverableErrors = [Int]()
            for index in runStart..<runEnd {
                switch toolCalls[index].status {
                case .error:
                    recoverableErrors.append(index)
                case .success:
                    hiddenIndices.formUnion(recoverableErrors)
                    recoverableErrors.removeAll(keepingCapacity: true)
                case .pending:
                    continue
                }
            }

            runStart = runEnd
        }

        return toolCalls.enumerated().compactMap { index, toolCall in
            hiddenIndices.contains(index) ? nil : toolCall
        }
    }

    static func summary(for toolCall: ToolCall) -> Summary {
        if displayName(for: toolCall) == "Prompt Preview" {
            return Summary(
                primaryText: "Prompt Preview",
                secondaryText: nil,
                showsToolList: false
            )
        }

        if let normalizedSummary = normalizedSummary(from: toolCall.result) {
            return Summary(
                primaryText: normalizedSummary,
                secondaryText: entitiesTouchedSummary(from: toolCall.result),
                showsToolList: false
            )
        }

        if let errorText = legacyErrorText(from: toolCall.result) {
            return Summary(
                primaryText: errorText,
                secondaryText: toolCall.name,
                showsToolList: false
            )
        }

        return Summary(
            primaryText: displayName(for: toolCall),
            secondaryText: nil,
            showsToolList: false
        )
    }

    static func detailSections(for toolCall: ToolCall) -> [ChatToolDetailSection] {
        var sections = [
            ChatToolDetailSection(
                kind: .summary,
                title: "Summary",
                subtitle: nil,
                isCollapsible: false,
                startsExpanded: true
            )
        ]

        if !ToolResultWorkspaceSurfaceParser.parse(toolCall).isEmpty {
            sections.append(
                ChatToolDetailSection(
                    kind: .workspaceActions,
                    title: "Workspace",
                    subtitle: "Open what this skill produced",
                    isCollapsible: false,
                    startsExpanded: true
                )
            )
        }

        return sections
    }

    private static func normalizedSummary(from result: AnyCodable?) -> String? {
        guard let payload = resultPayload(from: result) else {
            return nil
        }

        if let summary = payload["summary"] as? String {
            return summary.trimmedOrNil
        }

        if let dataPayload = payload["data"] as? [String: Any],
           let summary = dataPayload["summary"] as? String {
            return summary.trimmedOrNil
        }

        return nil
    }

    private static func entitiesTouchedSummary(from result: AnyCodable?) -> String? {
        guard let payload = resultPayload(from: result) else {
            return nil
        }

        let entities = (payload["entities_touched"] as? [[String: Any]])
            ?? ((payload["data"] as? [String: Any])?["entities_touched"] as? [[String: Any]])
            ?? []
        guard !entities.isEmpty else {
            return nil
        }

        let changes = entities.compactMap { ($0["change"] as? String)?.trimmedOrNil }
        let entityNames = entities.compactMap { entityDisplayName(from: $0) }
        guard !entityNames.isEmpty else {
            return nil
        }

        if let firstChange = changes.first,
           changes.allSatisfy({ $0.caseInsensitiveCompare(firstChange) == .orderedSame }) {
            return "\(firstChange.capitalized) \(joinedList(entityNames))"
        }

        let fragments = zip(entityNames.indices, entityNames).map { index, entityName in
            if index < changes.count {
                return "\(changes[index].capitalized) \(entityName)"
            }
            return entityName.capitalized
        }

        return joinedList(fragments)
    }

    private static func legacyErrorText(from result: AnyCodable?) -> String? {
        guard let payload = resultPayload(from: result) else {
            return nil
        }

        if let error = payload["error"] as? String {
            return error.trimmedOrNil
        }

        if let dataPayload = payload["data"] as? [String: Any],
           let error = dataPayload["error"] as? String {
            return error.trimmedOrNil
        }

        return nil
    }

    private static func entityDisplayName(from entity: [String: Any]) -> String? {
        let preferredKeys = ["title", "name", "label", "entity_name"]
        for key in preferredKeys {
            if let value = entity[key] as? String,
               let trimmed = value.trimmedOrNil {
                return trimmed
            }
        }

        if let entityType = entity["entity_type"] as? String,
           let trimmed = entityType.trimmedOrNil {
            return trimmed.replacingOccurrences(of: "_", with: " ")
        }

        return nil
    }

    private static func joinedList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            return values.dropLast().joined(separator: ", ") + ", and " + (values.last ?? "")
        }
    }

    private static func resultPayload(from result: AnyCodable?) -> [String: Any]? {
        result?.value as? [String: Any]
    }

    private static func toolFamily(for toolCall: ToolCall) -> String {
        (toolCall.skillId?.trimmedOrNil ?? toolCall.name.trimmedOrNil ?? toolCall.id).lowercased()
    }
}
