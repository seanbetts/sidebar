#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct SideBarMarkdown: View, Equatable {
    let text: String
    let preprocessor: (String) -> String
    private let maxImageSize = CGSize(width: 450, height: 450)

    init(text: String, preprocessor: @escaping (String) -> String = MarkdownRendering.normalizeTaskLists) {
        self.text = text
        self.preprocessor = preprocessor
    }

    static func == (lhs: SideBarMarkdown, rhs: SideBarMarkdown) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        #if canImport(MarkdownUI)
        Markdown(preprocessor(text))
            .markdownTheme(markdownTheme)
            .markdownBlockStyle(\.codeBlock) { configuration in
                CodeBlockTextView(text: configuration.content)
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
                    .padding(16)
                    .background(codeBlockBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .markdownMargin(top: .rem(1), bottom: .rem(1))
            }
            .markdownTextStyle(\.link) {
                ForegroundColor(.accentColor)
                UnderlineStyle(.single)
            }
            .markdownImageProvider(CappedImageProvider(maxSize: maxImageSize))
        #else
        Text(text)
        #endif
    }

    private var codeBlockBackground: Color {
        DesignTokens.Colors.muted
    }

    #if canImport(MarkdownUI)
    private var markdownTheme: Theme {
        Theme()
            .text {
                ForegroundColor(DesignTokens.Colors.textPrimary)
                BackgroundColor(nil)
                FontSize(16)
            }
            .strong {
                FontWeight(.bold)
            }
            .strikethrough {
                StrikethroughStyle(.single)
                ForegroundColor(DesignTokens.Colors.textSecondary)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.875))
                ForegroundColor(DesignTokens.Colors.textPrimary)
                BackgroundColor(DesignTokens.Colors.muted)
            }
            .link {
                ForegroundColor(.accentColor)
            }
            .heading1 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .zero, bottom: .rem(0.3))
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(2))
                        ForegroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .rem(1), bottom: .rem(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                        ForegroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .rem(1), bottom: .rem(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.25))
                        ForegroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .rem(1), bottom: .rem(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.125))
                        ForegroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
            .heading5 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .rem(1), bottom: .rem(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.0625))
                        ForegroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
            .heading6 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.3))
                    .markdownMargin(top: .rem(1), bottom: .rem(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1))
                        ForegroundColor(DesignTokens.Colors.textPrimary)
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.7))
                    .markdownMargin(top: .rem(0.5), bottom: .rem(0.5))
            }
            .list { configuration in
                configuration.label
                    .markdownMargin(top: .rem(0.5), bottom: .rem(0.5))
                    .relativePadding(.leading, length: .em(1.5))
            }
            .listItem { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.4))
                    .markdownMargin(top: .zero, bottom: .zero)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(DesignTokens.Colors.border)
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(DesignTokens.Colors.textSecondary)
                        }
                        .relativeLineSpacing(.em(0.7))
                        .relativePadding(.leading, length: .em(1))
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: .em(1), bottom: .em(1))
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: DesignTokens.Colors.border))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(
                            DesignTokens.Colors.background,
                            DesignTokens.Colors.muted.opacity(0.4)
                        )
                    )
                    .markdownMargin(top: .rem(0.75), bottom: .rem(0.75))
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.7))
                    .relativePadding(.horizontal, length: .em(0.75))
                    .relativePadding(.vertical, length: configuration.row == 0 ? .em(0.65) : .em(0.5))
                    .background(configuration.row == 0 ? DesignTokens.Colors.muted : Color.clear)
            }
    }
    #endif

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
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        textView.font = UIFont.monospacedSystemFont(
            ofSize: baseFont.pointSize * 0.875,
            weight: .regular
        )
        textView.textColor = UIColor.label
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let font = UIFont.monospacedSystemFont(
            ofSize: baseFont.pointSize * 0.875,
            weight: .regular
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.pointSize * 0.5
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: font,
            .foregroundColor: UIColor.label
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        if uiView.attributedText.string != text || uiView.attributedText.length == 0 {
            uiView.attributedText = attributed
        } else {
            uiView.typingAttributes = attributes
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
        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        textView.font = NSFont.monospacedSystemFont(
            ofSize: baseFont.pointSize * 0.875,
            weight: .regular
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseFont.pointSize * 0.5
        textView.defaultParagraphStyle = paragraphStyle
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
