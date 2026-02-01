import SwiftUI

public enum WorkspaceColumn: String {
    case primary
    case secondary
}

private struct WorkspaceColumnKey: EnvironmentKey {
    static let defaultValue: WorkspaceColumn = .primary
}

extension EnvironmentValues {
    var workspaceColumn: WorkspaceColumn {
        get { self[WorkspaceColumnKey.self] }
        set { self[WorkspaceColumnKey.self] = newValue }
    }
}
