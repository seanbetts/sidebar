import SwiftUI
import sideBarShared

enum HeaderStatusRowActionResult: Equatable {
    case resolved
    case retained
    case failed(String)
}

struct HeaderStatusActionPresentationState: Equatable {
    let inFlightRowID: String?
    let inFlightActionID: String?

    init(
        inFlightActionID: String? = nil,
        inFlightRowID: String? = nil
    ) {
        self.inFlightRowID = inFlightRowID
        self.inFlightActionID = inFlightActionID
    }

    func isDisabled(actionID: String) -> Bool {
        inFlightActionID == actionID
    }

    func showsLoadingIndicator(actionID: String) -> Bool {
        inFlightActionID == actionID
    }

    func isDisabled(rowID: String, actionID: String) -> Bool {
        inFlightRowID == rowID && inFlightActionID == actionID
    }

    func showsLoadingIndicator(rowID: String, actionID: String) -> Bool {
        inFlightRowID == rowID && inFlightActionID == actionID
    }
}

struct HeaderStatusPopoverState: Equatable {
    let rows: [HeaderStatusRowModel]
    let inlineErrorByRowID: [String: String]
    let shouldDismiss: Bool

    init(
        rows: [HeaderStatusRowModel],
        inlineErrorByRowID: [String: String] = [:],
        shouldDismiss: Bool = false
    ) {
        self.rows = rows
        self.inlineErrorByRowID = inlineErrorByRowID
        self.shouldDismiss = shouldDismiss
    }

    func removingResolvedRow(id: String) -> HeaderStatusPopoverState {
        let remainingRows = rows.filter { $0.id != id }
        let remainingErrors = inlineErrorByRowID.filter { $0.key != id }

        return HeaderStatusPopoverState(
            rows: remainingRows,
            inlineErrorByRowID: remainingErrors,
            shouldDismiss: remainingRows.isEmpty
        )
    }

    func applyingFailure(rowID: String, message: String) -> HeaderStatusPopoverState {
        var nextErrors = inlineErrorByRowID
        nextErrors[rowID] = message

        return HeaderStatusPopoverState(
            rows: rows,
            inlineErrorByRowID: nextErrors,
            shouldDismiss: false
        )
    }
}

struct HeaderStatusPopover: View {
    let model: HeaderStatusPopoverModel
    let actionState: HeaderStatusActionPresentationState
    let popoverState: HeaderStatusPopoverState
    let onAction: (HeaderStatusRowModel, HeaderStatusActionModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(model.title)
                .appFont(.subheading)

            if let message = effectiveMessage {
                Text(message)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !popoverState.rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(popoverState.rows.enumerated()), id: \.element.id) { index, row in
                        HeaderStatusRowView(
                            row: row,
                            actionState: actionState,
                            inlineError: popoverState.inlineErrorByRowID[row.id],
                            onAction: onAction
                        )

                        if index < popoverState.rows.count - 1 {
                            Divider()
                                .overlay(DesignTokens.Colors.border.opacity(0.5))
                                .padding(.vertical, DesignTokens.Spacing.xs)
                        }
                    }
                }
                .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var effectiveMessage: String? {
        switch (model.tone, popoverState.rows.isEmpty) {
        case (.error, false):
            return nil
        default:
            return model.message
        }
    }
}

private struct HeaderStatusRowView: View {
    let row: HeaderStatusRowModel
    let actionState: HeaderStatusActionPresentationState
    let inlineError: String?
    let onAction: (HeaderStatusRowModel, HeaderStatusActionModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxsPlus) {
            ViewThatFits(in: .horizontal) {
                horizontalRowLayout
                verticalRowLayout
            }

            if let inlineError, !inlineError.isEmpty {
                Text(inlineError)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
    }

    private var horizontalRowLayout: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            rowCopy
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            rowActionRail
        }
    }

    private var verticalRowLayout: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            rowCopy
                .frame(maxWidth: .infinity, alignment: .leading)

            if !row.actions.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    rowActionRail
                }
            }
        }
    }

    private var rowCopy: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(row.title)
                .appFont(.subheading)
                .lineLimit(2)
                .truncationMode(.tail)

            if let detail = row.detail, !detail.isEmpty {
                Text(detail)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var rowActionRail: some View {
        if !row.actions.isEmpty {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(row.actions) { action in
                    Button(role: buttonRole(for: action.role)) {
                        onAction(row, action)
                    } label: {
                        Group {
                            if actionState.showsLoadingIndicator(rowID: row.id, actionID: action.id) {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(appIcon: actionAppIcon(action))
                                    .appFont(.body)
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    .buttonStyle(
                        HeaderStatusRowActionButtonStyle(
                            role: action.role,
                            isPrimary: isPrimaryAction(action)
                        )
                    )
                    .accessibilityLabel(action.title)
                    .disabled(actionState.isDisabled(rowID: row.id, actionID: action.id))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func isPrimaryAction(_ action: HeaderStatusActionModel) -> Bool {
        row.actions.first(where: { $0.role == .default })?.id == action.id
    }

    private func actionAppIcon(_ action: HeaderStatusActionModel) -> AppIcon {
        switch action.role {
        case .default:
            return AppIcon.State.retry
        case .cancel:
            return AppIcon.Action.close
        case .destructive:
            return AppIcon.Action.close
        }
    }

    private func buttonRole(for role: HeaderStatusActionRole) -> ButtonRole? {
        switch role {
        case .default:
            return nil
        case .cancel:
            return .cancel
        case .destructive:
            return .destructive
        }
    }
}

private struct HeaderStatusRowActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let role: HeaderStatusActionRole
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxsPlus)
            .frame(minWidth: minimumWidth, minHeight: 32)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        if isPrimary {
            return DesignTokens.Colors.actionPrimary
        }

        switch role {
        case .destructive:
            return DesignTokens.Colors.error
        case .default, .cancel:
            return DesignTokens.Colors.textPrimary
        }
    }

    private var borderColor: Color {
        if isPrimary {
            return DesignTokens.Colors.actionPrimary.opacity(0.36)
        }

        switch role {
        case .destructive:
            return DesignTokens.Colors.errorBorder
        case .default, .cancel:
            return DesignTokens.Colors.border
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let baseColor: Color
        if isPrimary {
            baseColor = DesignTokens.Colors.selection
        } else {
            switch role {
            case .destructive:
                baseColor = DesignTokens.Colors.errorBackground
            case .default, .cancel:
                baseColor = DesignTokens.Colors.background
            }
        }

        return isPressed ? baseColor.opacity(0.82) : baseColor
    }

    private var minimumWidth: CGFloat {
        36
    }
}
