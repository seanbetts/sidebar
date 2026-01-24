#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

// MARK: - SideBarMarkdown

struct SideBarMarkdownLayout {
    static let maxContentWidth: CGFloat = 800
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
    static let blockSpacing: CGFloat = 16
    static let gallerySpacing: CGFloat = 12
    static let galleryMinImageWidth: CGFloat = 150
    static let maxImageSize = CGSize(width: 450, height: 450)
}

struct SideBarMarkdownStyle: Equatable {
    let codeBackground: Color
    let codeBlockBackground: Color

    static let `default` = SideBarMarkdownStyle(
        codeBackground: DesignTokens.Colors.muted,
        codeBlockBackground: DesignTokens.Colors.muted
    )

    static let chat = SideBarMarkdownStyle(
        codeBackground: DesignTokens.Colors.background,
        codeBlockBackground: DesignTokens.Colors.background
    )
}

struct SideBarMarkdownContainer: View {
    let text: String
    let style: SideBarMarkdownStyle

    init(text: String, style: SideBarMarkdownStyle = .default) {
        self.text = text
        self.style = style
    }

    var body: some View {
        SideBarMarkdown(text: text, style: style)
            .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth, alignment: .leading)
            .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
            .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct SideBarMarkdown: View, Equatable {
    let text: String
    let style: SideBarMarkdownStyle

    init(text: String, style: SideBarMarkdownStyle = .default) {
        self.text = text
        self.style = style
    }

    static func == (lhs: SideBarMarkdown, rhs: SideBarMarkdown) -> Bool {
        lhs.text == rhs.text && lhs.style == rhs.style
    }

    var body: some View {
        #if canImport(MarkdownUI)
        let blocks = MarkdownRendering.normalizedBlocks(from: text)
        if blocks.isEmpty {
            styledMarkdown(text)
        } else {
            VStack(alignment: .leading, spacing: SideBarMarkdownLayout.blockSpacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .markdown(let content):
                        styledMarkdown(content)
                    case .gallery(let gallery):
                        MarkdownGalleryView(gallery: gallery)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        Text(text)
        #endif
    }

    #if canImport(MarkdownUI)
    private func styledMarkdown(_ content: String) -> some View {
        Markdown(content)
            .markdownTheme(markdownTheme)
            .markdownTextStyle(\.link) {
                ForegroundColor(.accentColor)
                UnderlineStyle(.single)
            }
            .markdownImageProvider(CappedImageProvider(maxSize: SideBarMarkdownLayout.maxImageSize))
    }

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
                BackgroundColor(style.codeBackground)
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
                let trimmed = rawMarkdown.trimmed
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
                        .relativeLineSpacing(.em(0.2))
                        .markdownMargin(top: .rem(0.5), bottom: .rem(0.5))
                }
            }
            .list { configuration in
                configuration.label
                    .markdownMargin(top: .rem(0.5), bottom: .rem(0.5))
                    .relativePadding(.leading, length: .em(0))
            }
            .listItem { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: .zero, bottom: .zero)
            }
            .bulletedListMarker(.disc)
            .taskListMarker { configuration in
                Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .imageScale(.small)
                    .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .padding(DesignTokens.Spacing.md)
                }
                .background(style.codeBlockBackground)
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
                    .markdownMargin(top: .rem(1.5), bottom: .rem(1.5))
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
                        .font(DesignTokens.Typography.display)
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

private struct MarkdownGalleryView: View {
    let gallery: MarkdownRendering.MarkdownGallery

    private let gridSpacing: CGFloat = SideBarMarkdownLayout.gallerySpacing
    private let minImageWidth: CGFloat = SideBarMarkdownLayout.galleryMinImageWidth
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let rows = chunked(gallery.imageUrls, size: columns(for: availableWidth))
        let imageWidth = imageWidth(for: availableWidth)
        VStack(alignment: .center, spacing: gridSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: gridSpacing) {
                    ForEach(rows[rowIndex], id: \.self) { urlString in
                        MarkdownGalleryImageView(
                            urlString: urlString,
                            maxSize: CGSize(
                                width: imageWidth,
                                height: SideBarMarkdownLayout.maxImageSize.height
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if let caption = gallery.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }

    private func columns(for availableWidth: CGFloat) -> Int {
        let effectiveWidth = max(availableWidth, minImageWidth)
        let count = Int((effectiveWidth + gridSpacing) / (minImageWidth + gridSpacing))
        return max(1, count)
    }

    private func imageWidth(for availableWidth: CGFloat) -> CGFloat {
        let effectiveWidth = max(availableWidth, minImageWidth)
        let columnCount = columns(for: availableWidth)
        let totalSpacing = gridSpacing * CGFloat(max(columnCount - 1, 0))
        let columnWidth = (effectiveWidth - totalSpacing) / CGFloat(columnCount)
        return min(columnWidth, SideBarMarkdownLayout.maxImageSize.width)
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [items] }
        var chunks: [[String]] = []
        var index = 0
        while index < items.count {
            let end = min(index + size, items.count)
            chunks.append(Array(items[index..<end]))
            index = end
        }
        return chunks
    }
}

private struct MarkdownGalleryImageView: View {
    let urlString: String
    let maxSize: CGSize

    var body: some View {
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                case .failure:
                    Image(systemName: "photo")
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
