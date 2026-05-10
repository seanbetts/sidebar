import Foundation
import sideBarShared
import SwiftUI

struct ChatToolActionListView: View {
    let actions: [ChatToolAction]
    let onAction: (ChatToolAction, ChatToolActionDecision?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                ChatToolActionCard(action: action, onAction: onAction)
            }
        }
    }
}

struct ChatToolActionCard: View {
    let action: ChatToolAction
    let onAction: (ChatToolAction, ChatToolActionDecision?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        switch action.kind {
        case .confirmation where isResolvedConfirmation:
            EmptyView()
        case .confirmation:
            confirmationControls
        case .undo where isResolvedUndo:
            EmptyView()
        case .undo:
            undoControls
        }
    }

    private var confirmationControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Decline",
                systemImage: "xmark",
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground
            ) {
                onAction(action, .decline)
            }

            actionButton(
                title: "Confirm",
                systemImage: "checkmark",
                foreground: primaryButtonForeground,
                background: primaryButtonBackground
            ) {
                onAction(action, .accept)
            }

            statusLabel
        }
    }

    private var undoControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Undo",
                systemImage: "arrow.uturn.backward",
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground
            ) {
                onAction(action, nil)
            }

            statusLabel
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action handler: @escaping () -> Void
    ) -> some View {
        Button(action: handler) {
            Label(title, systemImage: systemImage)
                .appFont(.subheadlineSemibold)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxsPlus)
                .frame(minHeight: DesignTokens.Size.compactFieldHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isPending)
        .opacity(isPending ? 1 : 0.62)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if action.status != .pending {
            Text(statusText)
                .appFont(.captionSemibold)
                .foregroundStyle(statusForeground)
        }
    }

    private var isPending: Bool {
        action.status == .pending
    }

    private var isResolvedConfirmation: Bool {
        action.status == .accepted || action.status == .declined
    }

    private var isResolvedUndo: Bool {
        action.status == .undone
    }

    private var statusText: String {
        switch action.status {
        case .pending:
            return ""
        case .running:
            return "Working"
        case .accepted:
            return "Confirmed"
        case .declined:
            return "Declined"
        case .undone:
            return "Undone"
        case .failed:
            return "Failed"
        }
    }

    private var statusForeground: Color {
        action.status == .failed ? DesignTokens.Colors.error : DesignTokens.Colors.textSecondary
    }

    private var primaryButtonBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var primaryButtonForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var secondaryButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var secondaryButtonForeground: Color {
        DesignTokens.Colors.textPrimary
    }
}
