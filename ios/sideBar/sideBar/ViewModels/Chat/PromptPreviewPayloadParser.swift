import Foundation
import sideBarShared

enum PromptPreviewPayloadParser {
    private static let promptKeys: Set<String> = [
        "system_prompt",
        "first_message_prompt",
        "system_prompt_sections",
        "first_message_prompt_sections",
        "prompt_report",
        "workspace_context_menu_actions"
    ]

    static func parseEventPayload(_ payload: [String: Any]) -> ChatPromptPreview {
        ChatPromptPreview(
            systemPrompt: payload["system_prompt"] as? String,
            firstMessagePrompt: payload["first_message_prompt"] as? String,
            systemPromptSections: promptSections(from: payload, key: "system_prompt_sections"),
            firstMessagePromptSections: promptSections(from: payload, key: "first_message_prompt_sections"),
            promptReport: promptReport(from: payload, key: "prompt_report"),
            workspaceContextMenuActions: contextMenuActions(
                from: payload,
                key: "workspace_context_menu_actions"
            )
        )
    }

    static func parseToolResult(_ result: AnyCodable?) -> ChatPromptPreview? {
        guard let resultPayload = result?.value as? [String: Any],
              let promptPayload = promptPayload(fromResultPayload: resultPayload) else {
            return nil
        }
        return parseEventPayload(promptPayload)
    }

    static func promptPayload(fromResultPayload payload: [String: Any]) -> [String: Any]? {
        if hasPromptPreviewContent(payload) {
            return payload
        }
        if let dataPayload = payload["data"] as? [String: Any],
           hasPromptPreviewContent(dataPayload) {
            return dataPayload
        }
        return nil
    }

    private static func hasPromptPreviewContent(_ payload: [String: Any]) -> Bool {
        !promptKeys.isDisjoint(with: payload.keys)
    }

    private static func promptSections(from payload: [String: Any], key: String) -> [ChatPromptSection] {
        guard let sectionItems = payload[key] as? [[String: Any]] else {
            return []
        }
        return sectionItems.compactMap { section in
            guard let id = section["id"] as? String,
                  let title = section["title"] as? String,
                  let source = section["source"] as? String,
                  let chars = intValue(from: section["chars"]) else {
                return nil
            }
            return ChatPromptSection(id: id, title: title, source: source, chars: chars)
        }
    }

    private static func promptReport(from payload: [String: Any], key: String) -> ChatPromptReport? {
        guard let reportPayload = payload[key] as? [String: Any] else {
            return nil
        }
        let systemPrompt = promptReportDocument(from: reportPayload["system_prompt"])
        let firstMessagePrompt = promptReportDocument(from: reportPayload["first_message_prompt"])
        if systemPrompt == nil && firstMessagePrompt == nil {
            return nil
        }
        return ChatPromptReport(
            systemPrompt: systemPrompt,
            firstMessagePrompt: firstMessagePrompt
        )
    }

    private static func promptReportDocument(from value: Any?) -> ChatPromptReportDocument? {
        guard let document = value as? [String: Any],
              let totalChars = intValue(from: document["total_chars"]),
              let maxChars = intValue(from: document["max_chars"]),
              let truncated = document["truncated"] as? Bool else {
            return nil
        }
        let sectionsRaw: [[String: Any]] = document["sections"] as? [[String: Any]] ?? []
        let sections: [ChatPromptSection] = sectionsRaw.compactMap { section in
            guard let id = section["id"] as? String,
                  let title = section["title"] as? String,
                  let source = section["source"] as? String,
                  let chars = intValue(from: section["chars"]) else {
                return nil
            }
            return ChatPromptSection(id: id, title: title, source: source, chars: chars)
        }
        return ChatPromptReportDocument(
            totalChars: totalChars,
            maxChars: maxChars,
            truncated: truncated,
            sections: sections
        )
    }

    private static func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private static func contextMenuActions(
        from payload: [String: Any],
        key: String
    ) -> [AgentWorkspaceContextMenuAction] {
        guard let actionNames = payload[key] as? [String] else {
            return []
        }
        var parsed: [AgentWorkspaceContextMenuAction] = []
        var seen: Set<AgentWorkspaceContextMenuAction> = []
        for actionName in actionNames {
            let normalized = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let action = AgentWorkspaceContextMenuAction(rawValue: normalized),
                  !seen.contains(action) else {
                continue
            }
            seen.insert(action)
            parsed.append(action)
        }
        return parsed
    }
}
