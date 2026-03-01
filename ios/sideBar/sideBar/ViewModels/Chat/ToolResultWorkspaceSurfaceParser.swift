import Foundation
import sideBarShared

struct ToolResultWorkspaceSurfaceTarget: Equatable, Identifiable {
    let surface: AgentWorkspaceSurfaceDescriptor
    let pane: WorkspacePane
    let label: String

    var id: String {
        "\(pane.rawValue):\(surface.surfaceId)"
    }
}

enum ToolResultWorkspaceSurfaceParser {
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
                        label: label
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
