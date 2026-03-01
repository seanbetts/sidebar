import Foundation

/// Compatibility adapter for bridging legacy `AppSection` routing with workspace descriptors.
enum WorkspaceLegacySectionAdapter {
    static func section(from descriptor: WorkspaceContentDescriptor?) -> AppSection? {
        guard let descriptor else { return nil }
        switch descriptor {
        case .builtIn(let section):
            return section
        case .empty, .agentSurface:
            return nil
        }
    }
}
