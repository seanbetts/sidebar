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
    case promptPreview
    case technicalDetail

    var id: String { rawValue }
}

struct ChatToolTechnicalDetailRow: Equatable, Identifiable {
    let key: String
    let value: String

    var id: String { key }
}

struct ChatToolTechnicalDetail: Equatable {
    let parameterRows: [ChatToolTechnicalDetailRow]
    let resultText: String?

    var hasContent: Bool {
        !parameterRows.isEmpty || resultText != nil
    }
}

enum ChatToolPresentation {
    struct Summary: Equatable {
        let primaryText: String
        let secondaryText: String?
        let showsToolList: Bool
    }

    static func summary(for toolCall: ToolCall) -> Summary {
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
            primaryText: toolCall.name,
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

        if PromptPreviewPayloadParser.parseToolResult(toolCall.result) != nil {
            sections.append(
                ChatToolDetailSection(
                    kind: .promptPreview,
                    title: "Prompt Preview",
                    subtitle: "Transparency into the assembled prompt",
                    isCollapsible: true,
                    startsExpanded: false
                )
            )
        }

        if let technicalDetail = technicalDetail(for: toolCall),
           technicalDetail.hasContent {
            sections.append(
                ChatToolDetailSection(
                    kind: .technicalDetail,
                    title: "Technical Detail",
                    subtitle: "Raw parameters and result payload",
                    isCollapsible: true,
                    startsExpanded: false
                )
            )
        }

        return sections
    }

    static func technicalDetail(for toolCall: ToolCall) -> ChatToolTechnicalDetail? {
        let parameterRows = toolCall.parameters
            .map { ChatToolTechnicalDetailRow(key: $0.key, value: formattedValue($0.value.value)) }
            .sorted { $0.key < $1.key }

        let resultText = toolCall.result.map { formattedValue($0.value) }
        let detail = ChatToolTechnicalDetail(parameterRows: parameterRows, resultText: resultText)
        return detail.hasContent ? detail : nil
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

    private static func formattedValue(_ value: Any) -> String {
        if let stringValue = value as? String {
            return stringValue
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        return String(describing: value)
    }
}
