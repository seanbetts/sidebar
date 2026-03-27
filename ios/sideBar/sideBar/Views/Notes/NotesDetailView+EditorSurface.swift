import SwiftUI

extension NotesDetailView {
    var supportedNoteSurface: some View {
        ZStack {
            if isShowingReadSurface || editorViewModel.isHoldingReadSurfaceDuringEditEntry {
                configuredReadSurface()
                    .allowsHitTesting(isShowingReadSurface && !editorViewModel.isHoldingReadSurfaceDuringEditEntry)
            }

            if isShowingEditorSurface {
                configuredEditorSurface
                    .opacity(editorViewModel.isHoldingReadSurfaceDuringEditEntry ? 0 : 1)
                    .allowsHitTesting(!editorViewModel.isHoldingReadSurfaceDuringEditEntry)
                    .accessibilityHidden(editorViewModel.isHoldingReadSurfaceDuringEditEntry)
            }
        }
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
        let resolvedInitialViewportOffset = initialViewportOffset ?? pendingReadSurfaceViewportOffset
        let viewportOffsetHandler = reportsViewportOffsetChanges ? handleReadViewportOffsetChange : nil
        return SelectableNoteReadView(
            document: currentReadDocument,
            maxContentWidth: contentMaxWidth,
            initialViewportOffset: resolvedInitialViewportOffset,
            initialViewportAnchorTarget: initialViewportAnchorTarget,
            initialViewportAnchorY: initialViewportAnchorY,
            onActivateEditing: activateReadSurfaceEditing,
            onActivateEditingWithViewport: activateReadSurfaceEditing,
            onViewportOffsetChange: viewportOffsetHandler
        )
    }

    @ViewBuilder
    var editorSurface: some View {
        configuredEditorSurface
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
            onEscape: handleEscapeKey
        )
        #endif
    }
}
