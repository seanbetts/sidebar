import SwiftUI

enum ChatInputReturnIntent: Equatable {
    case insertNewline
    case send
}

func chatInputReturnIntent(shiftPressed: Bool) -> ChatInputReturnIntent {
    shiftPressed ? .insertNewline : .send
}

struct ChatInputBar: View {
    static let chromeKind: GlassChrome.Kind = .field

    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let isEnabled: Bool
    let isSendEnabled: Bool
    let isAttachEnabled: Bool
    let onSend: () -> Void
    let onAttach: () -> Void

    var body: some View {
        ChatInputContainer {
            PlatformChatInputView(
                text: $text,
                measuredHeight: $measuredHeight,
                isEnabled: isEnabled,
                isSendEnabled: isSendEnabled,
                isAttachEnabled: isAttachEnabled,
                minHeight: minHeight,
                maxHeight: maxHeight,
                onSend: onSend,
                onAttach: onAttach
            )
            .allowsHitTesting(isEnabled)
            .frame(height: computedHeight)
            .modifier(GlassEffectModifier())
        }
        .frame(maxWidth: ChatLayout.maxContentWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .glassChrome(Self.chromeKind)
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
    let isAttachEnabled: Bool
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
            isAttachEnabled: isAttachEnabled,
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
            isAttachEnabled: isAttachEnabled,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onSend: onSend,
            onAttach: onAttach
        )
        #endif
    }
}
