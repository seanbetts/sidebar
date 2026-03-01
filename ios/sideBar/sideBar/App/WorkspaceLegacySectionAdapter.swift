import Foundation

/// Compatibility adapter for bridging legacy `AppSection` routing with workspace descriptors.
enum WorkspaceLegacySectionAdapter {
    static func section(from descriptor: WorkspaceContentDescriptor?) -> AppSection? {
        guard let descriptor else { return nil }
        switch descriptor {
        case .builtIn(let section):
            return section
        case .agentSurface:
            // Agent surfaces are currently driven from chat interactions.
            return .chat
        case .empty:
            return nil
        }
    }
}
