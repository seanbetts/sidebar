import Foundation
import sideBarShared

struct ToolResultWorkspaceSurfaceTarget: Equatable, Identifiable {
    let surface: AgentWorkspaceSurfaceDescriptor
    let pane: WorkspacePane
    let label: String
    let appIcon: AppIcon

    var id: String {
        "\(pane.rawValue):\(surface.surfaceId)"
    }
}

struct ToolResultWorkspaceOpenEntityTarget: Equatable, Identifiable {
    let request: WorkspaceEntityOpenRequest
    let label: String
    let appIcon: AppIcon

    var id: String {
        "\(request.pane.rawValue):\(request.entity.type):\(request.entity.id)"
    }
}

enum ToolResultWorkspaceSurfaceParser {
    static func parse(_ toolCall: ToolCall) -> [ToolResultWorkspaceSurfaceTarget] {
        let skillIcon = SkillIconResolver.appIcon(for: toolCall)
        var targets = parse(toolCall.result).map { target in
            ToolResultWorkspaceSurfaceTarget(
                surface: target.surface,
                pane: target.pane,
                label: target.label,
                appIcon: skillIcon
            )
        }
        if let promptPreview = PromptPreviewPayloadParser.parseToolResult(toolCall.result),
           let surface = PromptPreviewWorkspaceSurfaceFactory.makeSurface(from: promptPreview) {
            let promptPreviewTarget = ToolResultWorkspaceSurfaceTarget(
                surface: surface,
                pane: .primary,
                label: "Show System Prompt Preview",
                appIcon: skillIcon
            )
            if !targets.contains(where: { $0.id == promptPreviewTarget.id }) {
                targets.insert(promptPreviewTarget, at: 0)
            }
        }
        return targets
    }

    static func parse(toolCalls: [ToolCall]) -> [ToolResultWorkspaceSurfaceTarget] {
        var targets: [ToolResultWorkspaceSurfaceTarget] = []
        var seenTargetIDs: Set<String> = []

        for toolCall in toolCalls {
            for target in parse(toolCall) {
                guard seenTargetIDs.insert(target.id).inserted else { continue }
                targets.append(target)
            }
        }
        return targets
    }

    static func parse(_ result: AnyCodable?) -> [ToolResultWorkspaceSurfaceTarget] {
        guard let payload = result?.value as? [String: Any] else {
            return []
        }

        let patchPayloads = workspacePatchPayloads(from: payload)
        var targets: [ToolResultWorkspaceSurfaceTarget] = []
        var seenTargetIDs: Set<String> = []

        for patchPayload in patchPayloads {
            switch ChatWorkspacePatchParser.parse(data: AnyCodable(patchPayload)) {
            case .accepted(let actions, _):
                for action in actions {
                    guard case .presentAgentSurface(let surface, let pane) = action else {
                        continue
                    }
                    let label = "Show \(surfaceActionTitle(for: surface))"
                    let target = ToolResultWorkspaceSurfaceTarget(
                        surface: surface,
                        pane: pane,
                        label: label,
                        appIcon: AppIcon.Workspace.surface
                    )
                    if seenTargetIDs.insert(target.id).inserted {
                        targets.append(target)
                    }
                }
            case .rejected:
                continue
            }
        }
        return targets
    }

    private static func workspacePatchPayloads(
        from payload: [String: Any]
    ) -> [[String: Any]] {
        var patches: [[String: Any]] = []
        appendWorkspacePatches(from: payload, into: &patches)
        if let dataPayload = payload["data"] as? [String: Any] {
            appendWorkspacePatches(from: dataPayload, into: &patches)
        }
        return patches
    }

    private static func appendWorkspacePatches(
        from payload: [String: Any],
        into patches: inout [[String: Any]]
    ) {
        if let patch = payload["workspace_patch"] as? [String: Any] {
            patches.append(patch)
        }
        if let patchArray = payload["workspace_patches"] as? [[String: Any]] {
            patches.append(contentsOf: patchArray)
        }
    }

    private static func surfaceActionTitle(
        for surface: AgentWorkspaceSurfaceDescriptor
    ) -> String {
        if let title = surface.title?.trimmedOrNil {
            return title
        }
        let raw = surface.surfaceType.rawValue
        let withSpaces = raw.replacingOccurrences(
            of: "([A-Z])",
            with: " $1",
            options: .regularExpression
        )
        return withSpaces.prefix(1).uppercased() + withSpaces.dropFirst()
    }
}

enum ToolResultWorkspaceOpenEntityParser {
    static func parse(_ toolCall: ToolCall) -> [ToolResultWorkspaceOpenEntityTarget] {
        parse(toolCall.result)
    }

    static func parse(toolCalls: [ToolCall]) -> [ToolResultWorkspaceOpenEntityTarget] {
        var targets: [ToolResultWorkspaceOpenEntityTarget] = []
        var seenTargetIDs: Set<String> = []

        for toolCall in toolCalls {
            for target in parse(toolCall) {
                guard seenTargetIDs.insert(target.id).inserted else { continue }
                targets.append(target)
            }
        }
        return targets
    }

    static func parse(_ result: AnyCodable?) -> [ToolResultWorkspaceOpenEntityTarget] {
        guard let payload = result?.value as? [String: Any] else {
            return []
        }

        let patchPayloads = workspacePatchPayloads(from: payload)
        var targets: [ToolResultWorkspaceOpenEntityTarget] = []
        var seenTargetIDs: Set<String> = []

        for patchPayload in patchPayloads {
            switch ChatWorkspacePatchParser.parse(data: AnyCodable(patchPayload)) {
            case .accepted(let actions, _):
                for action in actions {
                    guard case .openEntity(let request) = action else {
                        continue
                    }
                    let target = ToolResultWorkspaceOpenEntityTarget(
                        request: request,
                        label: label(for: request),
                        appIcon: appIcon(for: request.entity.type)
                    )
                    if seenTargetIDs.insert(target.id).inserted {
                        targets.append(target)
                    }
                }
            case .rejected:
                continue
            }
        }
        return targets
    }

    private static func workspacePatchPayloads(
        from payload: [String: Any]
    ) -> [[String: Any]] {
        var patches: [[String: Any]] = []
        appendWorkspacePatches(from: payload, into: &patches)
        if let dataPayload = payload["data"] as? [String: Any] {
            appendWorkspacePatches(from: dataPayload, into: &patches)
        }
        return patches
    }

    private static func appendWorkspacePatches(
        from payload: [String: Any],
        into patches: inout [[String: Any]]
    ) {
        if let patch = payload["workspace_patch"] as? [String: Any] {
            patches.append(patch)
        }
        if let patchArray = payload["workspace_patches"] as? [[String: Any]] {
            patches.append(contentsOf: patchArray)
        }
    }

    private static func label(for request: WorkspaceEntityOpenRequest) -> String {
        if let title = request.entity.title?.trimmedOrNil {
            return "Open \(title)"
        }
        return "Open \(fallbackTitle(for: request.entity.type))"
    }

    private static func fallbackTitle(for entityType: String) -> String {
        switch entityType {
        case "note":
            return "Note"
        case "website":
            return "Website"
        case "file":
            return "File"
        case "conversation":
            return "Chat"
        case "scratchpad":
            return "Scratchpad"
        case "task", "task_scope", "task_project", "task_group":
            return "Tasks"
        default:
            let withSpaces = entityType.replacingOccurrences(
                of: "_",
                with: " "
            )
            return withSpaces.prefix(1).uppercased() + withSpaces.dropFirst()
        }
    }

    private static func appIcon(for entityType: String) -> AppIcon {
        switch entityType {
        case "note":
            return AppIcon.Content.textDocument
        case "website":
            return AppIcon.Domain.websites
        case "file":
            return AppIcon.Domain.files
        case "conversation":
            return AppIcon.Domain.chat
        case "scratchpad":
            return AppIcon.Action.compose
        case "task", "task_scope", "task_project", "task_group":
            return AppIcon.Domain.tasks
        default:
            return AppIcon.Workspace.openEntityFallback
        }
    }
}
