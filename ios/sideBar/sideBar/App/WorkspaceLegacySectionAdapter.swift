import Foundation

/// Compatibility adapter for bridging legacy `AppSection` routing with workspace descriptors.
struct WorkspaceLegacySectionProjection: Equatable {
    let primaryDescriptor: WorkspaceContentDescriptor
    let secondaryDescriptor: WorkspaceContentDescriptor
    let compactSelection: AppSection
}

enum WorkspaceLegacySectionAdapter {
    static func descriptor(for section: AppSection?) -> WorkspaceContentDescriptor {
        .fromOptionalBuiltInSection(section)
    }

    static func section(from descriptor: WorkspaceContentDescriptor?) -> AppSection? {
        guard let descriptor else { return nil }
        switch descriptor {
        case .builtIn(let section):
            return section
        case .empty, .agentSurface:
            return nil
        }
    }

    static func makeProjection(
        workspaceState: WorkspaceState,
        fallbackPrimarySection: AppSection?,
        fallbackSecondarySection: AppSection?,
        fallbackCompactSelection: AppSection?
    ) -> WorkspaceLegacySectionProjection {
        let primaryDescriptor = preferredDescriptor(
            workspaceState.primaryPane.descriptor,
            fallback: descriptor(for: fallbackPrimarySection)
        )

        let secondaryDescriptor: WorkspaceContentDescriptor
        if workspaceState.layout == .compact {
            secondaryDescriptor = .empty
        } else if let pane = workspaceState.secondaryPane {
            secondaryDescriptor = preferredDescriptor(
                pane.descriptor,
                fallback: descriptor(for: fallbackSecondarySection)
            )
        } else {
            secondaryDescriptor = descriptor(for: fallbackSecondarySection)
        }

        let compactSelection = section(from: workspaceState.primaryPane.descriptor)
            ?? fallbackCompactSelection
            ?? fallbackPrimarySection
            ?? .chat

        return WorkspaceLegacySectionProjection(
            primaryDescriptor: primaryDescriptor,
            secondaryDescriptor: secondaryDescriptor,
            compactSelection: compactSelection
        )
    }

    static func compactDetailDescriptor(
        for section: AppSection,
        projection: WorkspaceLegacySectionProjection
    ) -> WorkspaceContentDescriptor {
        if section == projection.compactSelection {
            return projection.primaryDescriptor
        }
        return .builtIn(section)
    }

    private static func preferredDescriptor(
        _ descriptor: WorkspaceContentDescriptor,
        fallback: WorkspaceContentDescriptor
    ) -> WorkspaceContentDescriptor {
        if case .empty = descriptor {
            return fallback
        }
        return descriptor
    }
}
