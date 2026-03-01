import Foundation

extension ChatViewModel {
    func dispatchPromptPreviewToWorkspace(_ preview: ChatPromptPreview) {
        guard let workspaceActionDispatcher,
              let surface = PromptPreviewWorkspaceSurfaceFactory.makeSurface(from: preview) else {
            return
        }
        workspaceActionDispatcher(.presentAgentSurface(surface, pane: .primary))
    }
}
