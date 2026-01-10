#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct SideBarMarkdown: View {
    let text: String
    let preprocessor: (String) -> String
    private let maxImageSize = CGSize(width: 450, height: 450)

    init(text: String, preprocessor: @escaping (String) -> String = MarkdownRendering.normalizeTaskLists) {
        self.text = text
        self.preprocessor = preprocessor
    }

    var body: some View {
        #if canImport(MarkdownUI)
        Markdown(preprocessor(text))
            .markdownTheme(.gitHub)
            .markdownBlockStyle(\.codeBlock) { configuration in
                CodeBlockTextView(text: configuration.content)
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
                    .padding(12)
                    .background(codeBlockBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .markdownMargin(top: RelativeSize.em(0.25), bottom: RelativeSize.em(0.75))
            }
            .markdownTextStyle(\.strikethrough) {
                StrikethroughStyle(.single)
                ForegroundColor(.secondary)
            }
            .markdownTextStyle(\.link) {
                UnderlineStyle(.single)
            }
            .markdownImageProvider(CappedImageProvider(maxSize: maxImageSize))
        #else
        Text(text)
        #endif
    }

    private var codeBlockBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

}

#if os(iOS)
private struct CodeBlockTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.heightTracksTextView = true
        textView.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        textView.textColor = UIColor.label
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
}
#elseif os(macOS)
private struct CodeBlockTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        textView.textColor = .labelColor
        textView.string = text
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
        }
    }
}
#endif

#if canImport(MarkdownUI)
private struct CappedImageProvider: ImageProvider {
    let maxSize: CGSize

    func makeImage(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                HStack {
                    Spacer(minLength: 0)
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                    Spacer(minLength: 0)
                }
            case .failure:
                HStack {
                    Spacer(minLength: 0)
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            case .empty:
                HStack {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }
            @unknown default:
                EmptyView()
            }
        }
    }
}
#endif
