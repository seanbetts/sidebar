import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let isSendEnabled: Bool
    let onSend: () -> Void
    let onAttach: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let maxInputWidth: CGFloat = 860

    var body: some View {
        ChatInputContainer {
            PlatformChatInputView(
                text: $text,
                measuredHeight: $measuredHeight,
                isEnabled: isEnabled,
                isSendEnabled: isSendEnabled,
                minHeight: minHeight,
                maxHeight: maxHeight,
                onSend: onSend,
                onAttach: onAttach
            )
            .frame(height: computedHeight)
            .modifier(GlassEffectModifier())
        }
        .frame(maxWidth: maxInputWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.mdPlus, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .bordered(color: borderColor, cornerRadius: DesignTokens.Radius.mdPlus)
        .appShadow(color: shadowColor, radius: shadowRadius, y: shadowRadius * 0.6)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        let color = DesignTokens.Colors.border
        return colorScheme == .dark ? color.opacity(0.95) : color.opacity(0.7)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 6 : 10
    }

    private var computedHeight: CGFloat {
        let clamped = min(max(measuredHeight, minHeight), maxHeight)
        return clamped
    }

    private var minHeight: CGFloat {
        #if os(macOS)
        return 84
        #else
        return 46
        #endif
    }

    private var maxHeight: CGFloat {
        #if os(macOS)
        return 240
        #else
        return 140
        #endif
    }
}

private struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct ChatInputContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

private struct PlatformChatInputView: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let isSendEnabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSend: () -> Void
    let onAttach: () -> Void

    var body: some View {
        #if os(iOS)
        ChatInputUIKitView(
            text: $text,
            measuredHeight: $measuredHeight,
            isEnabled: isEnabled,
            isSendEnabled: isSendEnabled,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onSend: onSend,
            onAttach: onAttach
        )
        #else
        ChatInputAppKitView(
            text: $text,
            measuredHeight: $measuredHeight,
            isEnabled: isEnabled,
            isSendEnabled: isSendEnabled,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onSend: onSend,
            onAttach: onAttach
        )
        #endif
    }
}
