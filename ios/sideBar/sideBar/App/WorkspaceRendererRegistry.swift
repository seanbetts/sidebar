import SwiftUI

/// Maps workspace descriptors to concrete SwiftUI renderers.
@MainActor
public struct WorkspaceRendererRegistry {
    public typealias EmptyRenderer = () -> AnyView
    public typealias BuiltInRenderer = (AppSection) -> AnyView
    public typealias AgentSurfaceRenderer = (AgentWorkspaceSurfaceDescriptor) -> AnyView

    private let emptyRenderer: EmptyRenderer
    private let builtInRenderer: BuiltInRenderer
    private let agentSurfaceRenderer: AgentSurfaceRenderer

    public init(
        emptyRenderer: @escaping EmptyRenderer,
        builtInRenderer: @escaping BuiltInRenderer,
        agentSurfaceRenderer: @escaping AgentSurfaceRenderer
    ) {
        self.emptyRenderer = emptyRenderer
        self.builtInRenderer = builtInRenderer
        self.agentSurfaceRenderer = agentSurfaceRenderer
    }

    public func render(_ descriptor: WorkspaceContentDescriptor) -> AnyView {
        switch descriptor {
        case .empty:
            return emptyRenderer()
        case .builtIn(let section):
            return builtInRenderer(section)
        case .agentSurface(let surface):
            return agentSurfaceRenderer(surface)
        }
    }
}
