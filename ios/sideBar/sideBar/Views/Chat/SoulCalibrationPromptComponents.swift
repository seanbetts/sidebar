import SwiftUI

struct CalibrationChoice: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { value }
}

struct ContinueButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    var style: ContinueButtonStyle = .primary

    enum ContinueButtonStyle {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.bodySemibold)
                .foregroundColor(titleColor)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(minWidth: 108)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var titleColor: Color {
        isEnabled ? selectedForegroundColor : DesignTokens.Colors.textSecondary
    }

    private var backgroundColor: Color {
        isEnabled ? selectedBackgroundColor : DesignTokens.Colors.muted
    }

    private var borderColor: Color {
        isEnabled ? selectedBorderColor : DesignTokens.Colors.border
    }

    private var selectedForegroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return DesignTokens.Colors.textPrimary
        }
    }

    private var selectedBackgroundColor: Color {
        switch style {
        case .primary:
            return .black
        case .secondary:
            return DesignTokens.Colors.surface
        }
    }

    private var selectedBorderColor: Color {
        switch style {
        case .primary:
            return .black
        case .secondary:
            return DesignTokens.Colors.border
        }
    }
}

enum CalibrationDisplayStep: Equatable {
    case primaryGoal
    case workingRelationship
    case tonePreferences
    case nameConfirmation

    init(prompt: OnboardingCalibrationPrompt) {
        switch prompt {
        case .primaryGoal:
            self = .primaryGoal
        case .workingRelationship:
            self = .workingRelationship
        case .tonePreferences:
            self = .tonePreferences
        }
    }

    var previous: CalibrationDisplayStep? {
        switch self {
        case .primaryGoal:
            return nil
        case .workingRelationship:
            return .primaryGoal
        case .tonePreferences:
            return .workingRelationship
        case .nameConfirmation:
            return .tonePreferences
        }
    }

    var progressIndex: Int {
        switch self {
        case .primaryGoal:
            return 0
        case .workingRelationship:
            return 1
        case .tonePreferences:
            return 2
        case .nameConfirmation:
            return 3
        }
    }
}

struct SoulCalibrationChoiceChip: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.bodySemibold)
                .foregroundColor(foregroundColor)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(chipBackground)
                .overlay(chipBorder)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(selectedBackgroundColor)
        } else if !isEnabled {
            Capsule()
                .fill(disabledBackgroundColor)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(DesignTokens.Colors.surface)
        }
    }

    @ViewBuilder
    private var chipBorder: some View {
        if isSelected {
            Capsule()
                .stroke(selectedBackgroundColor, lineWidth: 1)
        } else {
            Capsule()
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        }
    }

    private var foregroundColor: Color {
        if isSelected {
            return selectedForegroundColor
        }
        if !isEnabled {
            return DesignTokens.Colors.textSecondary
        }
        return DesignTokens.Colors.textPrimary
    }

    private var selectedForegroundColor: Color {
        .white
    }

    private var selectedBackgroundColor: Color {
        .black
    }

    private var disabledBackgroundColor: Color {
        DesignTokens.Colors.muted.opacity(0.55)
    }
}

struct FlexibleChipLayout<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ChipFlowLayout(itemSpacing: spacing, lineSpacing: lineSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SoulCalibrationNameBadge<CenterContent: View>: View {
    @ViewBuilder let centerContent: () -> CenterContent

    var body: some View {
        VStack(spacing: 0) {
            Text("HELLO, I'M")
                .appFont(.captionSemibold)
                .foregroundColor(.white)
                .tracking(1.2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background(Color.black)

            centerContent()
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.white)

            Rectangle()
                .fill(Color.black)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }
}

struct SoulCalibrationFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Rectangle()
                .fill(DesignTokens.Colors.border)
                .frame(height: 1)

            content()
        }
        .padding(.top, DesignTokens.Spacing.xs)
    }
}

struct SoulCalibrationFooterProgressIndicator: View {
    var body: some View {
        LoadingIndicatorView(size: LoadingIndicatorSize.control)
            .frame(
                width: LoadingIndicatorSize.control,
                height: LoadingIndicatorSize.control
            )
    }
}

struct ChipFlowLayout: Layout {
    let itemSpacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            usedWidth = max(usedWidth, currentX + size.width)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + itemSpacing
        }

        return CGSize(width: usedWidth, height: currentY + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + itemSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
