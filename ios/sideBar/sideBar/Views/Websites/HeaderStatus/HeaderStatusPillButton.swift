import SwiftUI

struct HeaderStatusPillButton: View {
    let pill: HeaderStatusPillModel
    let onAction: (HeaderStatusRowModel, HeaderStatusActionModel) async -> HeaderStatusRowActionResult

    @State private var isPresented = false
    @State private var actionState = HeaderStatusActionPresentationState()
    @State private var popoverState: HeaderStatusPopoverState

    init(
        pill: HeaderStatusPillModel,
        onAction: @escaping (HeaderStatusRowModel, HeaderStatusActionModel) async -> HeaderStatusRowActionResult = { _, _ in
            .retained
        }
    ) {
        self.pill = pill
        self.onAction = onAction
        _popoverState = State(initialValue: HeaderStatusPopoverState(rows: pill.popover.rows))
    }

    var body: some View {
        StatusPill(
            title: pill.label,
            tone: pill.tone.statusPillTone,
            action: { isPresented = true },
            accessibilityLabel: pill.accessibilityLabel
        )
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            MacPopoverShell(
                type: headerStatusPopoverPanelType(),
                presentationBackground: .appBackground
            ) {
                HeaderStatusPopover(
                    model: pill.popover,
                    actionState: actionState,
                    popoverState: popoverState,
                    onAction: handleAction
                )
            }
            .presentationCompactAdaptation(.sheet)
        }
        .onChange(of: pill.popover) { _, _ in
            actionState = HeaderStatusActionPresentationState()
            popoverState = HeaderStatusPopoverState(rows: pill.popover.rows)
        }
    }

    private func handleAction(row: HeaderStatusRowModel, action: HeaderStatusActionModel) {
        guard !actionState.isDisabled(rowID: row.id, actionID: action.id) else {
            return
        }

        actionState = HeaderStatusActionPresentationState(
            inFlightActionID: action.id,
            inFlightRowID: row.id
        )

        Task {
            let result = await onAction(row, action)
            await MainActor.run {
                actionState = HeaderStatusActionPresentationState()

                switch result {
                case .resolved:
                    popoverState = popoverState.removingResolvedRow(id: row.id)
                    if popoverState.shouldDismiss {
                        isPresented = false
                    }
                case .retained:
                    break
                case let .failed(message):
                    popoverState = popoverState.applyingFailure(rowID: row.id, message: message)
                }
            }
        }
    }
}

private extension HeaderStatusTone {
    var statusPillTone: StatusPillTone {
        switch self {
        case .progress:
            return .loading
        case .warning:
            return .warning
        case .error:
            return .error
        case .success:
            return .success
        }
    }
}
