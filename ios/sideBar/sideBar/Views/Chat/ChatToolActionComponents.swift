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
        switch action.status {
        case .failed:
            retryControls
        default:
            switch action.kind {
            case .confirmation where isResolvedConfirmation:
                EmptyView()
            case .undo where isResolvedUndo:
                EmptyView()
            case .confirmation:
                confirmationControls
            case .undo:
                undoControls
            }
        }
    }

    private var confirmationControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Decline",
                icon: AppIcon.Action.close,
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground
            ) {
                onAction(action, .decline)
            }

            actionButton(
                title: "Confirm",
                icon: AppIcon.State.success,
                foreground: primaryButtonForeground,
                background: primaryButtonBackground
            ) {
                onAction(action, .accept)
            }
        }
    }

    private var undoControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Undo",
                icon: AppIcon.Action.undo,
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground
            ) {
                onAction(action, nil)
            }
        }
    }

    private var retryControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Retry",
                icon: AppIcon.State.retry,
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground,
                isEnabled: true
            ) {
                onAction(action, nil)
            }
        }
    }

    private func actionButton(
        title: String,
        icon: AppIcon,
        foreground: Color,
        background: Color,
        isEnabled: Bool? = nil,
        action handler: @escaping () -> Void
    ) -> some View {
        let canTap = isEnabled ?? isPending
        return Button(action: handler) {
            Label(title, systemImage: icon.rawValue)
                .appFont(.subheading)
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
        .disabled(!canTap)
        .opacity(canTap ? 1 : 0.62)
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
