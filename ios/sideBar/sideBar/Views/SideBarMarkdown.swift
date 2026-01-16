#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct SideBarMarkdown: View, Equatable {
    let text: String
    let preprocessor: (String) -> String
    private let maxImageSize = CGSize(width: 450, height: 450)

    init(text: String, preprocessor: @escaping (String) -> String = MarkdownRendering.normalizeNoteMarkdown) {
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
            .markdownTextStyle(\.link) {
                ForegroundColor(.accentColor)
                UnderlineStyle(.single)
            }
            .markdownImageProvider(CappedImageProvider(maxSize: maxImageSize))
        #else
        Text(text)
        #endif
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
                UnderlineStyle(.single)
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
                let rawMarkdown = configuration.content.renderMarkdown()
                let trimmed = rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix(MarkdownRendering.imageCaptionMarker) {
                    let caption = trimmed
                        .dropFirst(MarkdownRendering.imageCaptionMarker.count)
                        .trimmingCharacters(in: .whitespaces)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .markdownMargin(top: .rem(0.25), bottom: .rem(0.75))
                } else {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.7))
                        .markdownMargin(top: .rem(0.5), bottom: .rem(0.5))
                }
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
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.5))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.875))
                            ForegroundColor(DesignTokens.Colors.textPrimary)
                            BackgroundColor(nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(DesignTokens.Colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
                .markdownMargin(top: .rem(1), bottom: .rem(1))
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
                let isHeader = configuration.row == 0
                return configuration.label
                    .markdownTextStyle {
                        if isHeader {
                            FontWeight(.semibold)
                        }
                        BackgroundColor(nil)
                    }
                    .relativeLineSpacing(.em(0.7))
                    .relativePadding(.horizontal, length: .em(0.75))
                    .relativePadding(.vertical, length: isHeader ? .em(0.65) : .em(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(isHeader ? DesignTokens.Colors.muted : Color.clear)
            }
            .thematicBreak {
                Divider()
                    .frame(height: 1)
                    .overlay(DesignTokens.Colors.border)
                    .markdownMargin(top: .rem(1.5), bottom: .rem(0.5))
            }
    }
    #endif

}


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
