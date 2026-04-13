import SwiftUI

extension NotesDetailView {
    private var hiddenSurfaceOffscreenOffset: CGFloat { 20_000 }

    var supportedNoteSurface: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.activeNote != nil && currentUnsupportedContent == nil {
                configuredReadSurface()
                    .zIndex(editorViewModel.isHoldingEditorSurfaceDuringReadExit ? 0 : 0)
                    .opacity(
                        isReadSurfaceVisibleForCurrentPresentation
                            ? (editorViewModel.isHoldingEditorSurfaceDuringReadExit ? 0 : 1)
                            : 0
                    )
                    .allowsHitTesting(
                        isShowingReadSurface
                            && !editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            && !editorViewModel.isHoldingEditorSurfaceDuringReadExit
                    )
                    .offset(
                        x: editorViewModel.isHoldingEditorSurfaceDuringReadExit
                            ? hiddenSurfaceOffscreenOffset
                            : 0
                    )
                    .accessibilityHidden(!isReadSurfaceVisibleForCurrentPresentation)
            }

            if isShowingEditorSurface || editorViewModel.isHoldingEditorSurfaceDuringReadExit {
                configuredEditorSurface
                    .zIndex(1)
                    .opacity(
                        editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            ? 0
                            : 1
                    )
                    .allowsHitTesting(
                        isShowingEditorSurface
                            && !editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            && !editorViewModel.isHoldingEditorSurfaceDuringReadExit
                    )
                    .offset(
                        x: editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            ? hiddenSurfaceOffscreenOffset
                            : 0
                    )
                    .accessibilityHidden(
                        editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            || editorViewModel.isHoldingEditorSurfaceDuringReadExit
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var readSurface: some View {
        configuredReadSurface()
    }

    func configuredReadSurface(
        initialViewportOffset: CGPoint? = nil,
        initialViewportAnchorTarget: NotesEditorViewModel.PendingEditSelectionTarget? = nil,
        initialViewportAnchorY: CGFloat? = nil,
        reportsViewportOffsetChanges: Bool = true
    ) -> some View {
        let resolvedInitialViewportAnchorTarget =
            initialViewportAnchorTarget ?? editorViewModel.pendingReadSurfaceViewportAnchorTarget
        let resolvedInitialViewportAnchorY =
            initialViewportAnchorY ?? editorViewModel.pendingReadSurfaceViewportAnchorY
        let resolvedInitialViewportOffset =
            initialViewportOffset ?? editorViewModel.pendingReadSurfaceViewportOffset
        let viewportOffsetHandler = reportsViewportOffsetChanges ? handleReadViewportOffsetChange : nil
        return SelectableNoteReadView(
            document: currentReadDocument,
            maxContentWidth: contentMaxWidth,
            initialViewportOffset: resolvedInitialViewportOffset,
            initialViewportAnchorTarget: resolvedInitialViewportAnchorTarget,
            initialViewportAnchorY: resolvedInitialViewportAnchorY,
            presentationGeneration: editorViewModel.readSurfacePresentationGeneration,
            onActivateEditing: activateReadSurfaceEditing,
            onActivateEditingWithViewport: activateReadSurfaceEditing,
            onToggleChecklistItem: handleReadSurfaceChecklistToggle,
            onViewportOffsetChange: viewportOffsetHandler,
            onInitialViewportRestorationApplied: handleReadInitialViewportRestorationApplied
        )
    }

    @ViewBuilder
    var editorSurface: some View {
        configuredEditorSurface
    }

    var isReadSurfaceVisibleForCurrentPresentation: Bool {
        isShowingReadSurface
            || editorViewModel.isHoldingReadSurfaceDuringEditEntry
            || editorViewModel.isHoldingEditorSurfaceDuringReadExit
    }

    @ViewBuilder
    var configuredEditorSurface: some View {
        #if os(iOS)
        AttributedNoteEditorContainer(
            editorViewModel: editorViewModel,
            maxContentWidth: contentMaxWidth,
            onFormattingBarPresentationChange: handleFormattingBarPresentationChange,
            onInitialPresentationReady: {
                editorViewModel.completeEditEntryPresentationHold()
            },
            onEscape: handleEscapeKey
        )
        #else
        AttributedNoteEditorContainer(
            editorViewModel: editorViewModel,
            maxContentWidth: contentMaxWidth,
            onInitialPresentationReady: {
                editorViewModel.completeEditEntryPresentationHold()
            },
            onEscape: handleEscapeKey
        )
        #endif
    }
}
