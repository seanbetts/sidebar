import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class WorkspaceRendererRegistryTests: XCTestCase {
    func testRenderEmptyInvokesEmptyRenderer() {
        var emptyRenderCount = 0
        let registry = WorkspaceRendererRegistry(
            emptyRenderer: {
                emptyRenderCount += 1
                return AnyView(EmptyView())
            },
            builtInRenderer: { _ in
                XCTFail("Built-in renderer should not be called for .empty")
                return AnyView(EmptyView())
            },
            agentSurfaceRenderer: { _ in
                XCTFail("Agent renderer should not be called for .empty")
                return AnyView(EmptyView())
            }
        )

        _ = registry.render(.empty)

        XCTAssertEqual(emptyRenderCount, 1)
    }

    func testRenderBuiltInInvokesBuiltInRendererWithSection() {
        var renderedSection: AppSection?
        let registry = WorkspaceRendererRegistry(
            emptyRenderer: { AnyView(EmptyView()) },
            builtInRenderer: { section in
                renderedSection = section
                return AnyView(EmptyView())
            },
            agentSurfaceRenderer: { _ in
                XCTFail("Agent renderer should not be called for built-in section")
                return AnyView(EmptyView())
            }
        )

        _ = registry.render(.builtIn(.notes))

        XCTAssertEqual(renderedSection, .notes)
    }

    func testRenderAgentSurfaceInvokesAgentRendererWithDescriptor() {
        var renderedSurface: AgentWorkspaceSurfaceDescriptor?
        let registry = WorkspaceRendererRegistry(
            emptyRenderer: { AnyView(EmptyView()) },
            builtInRenderer: { _ in
                XCTFail("Built-in renderer should not be called for agent surface")
                return AnyView(EmptyView())
            },
            agentSurfaceRenderer: { surface in
                renderedSurface = surface
                return AnyView(EmptyView())
            }
        )

        let surface = AgentWorkspaceSurfaceDescriptor(
            type: "chart",
            surfaceId: "surface-123",
            title: "Revenue"
        )
        _ = registry.render(.agentSurface(surface))

        XCTAssertEqual(renderedSurface, surface)
    }
}
