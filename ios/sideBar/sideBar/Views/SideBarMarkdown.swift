#if canImport(MarkdownUI)
import MarkdownUI
import sideBarShared
#endif
import SwiftUI

// MARK: - SideBarMarkdown

struct SideBarMarkdownLayout {
    static let maxContentWidth: CGFloat = ContentLayout.maxContentWidth
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

enum SideBarMarkdownRenderingContext: Equatable {
    case standard
    case website
}

struct SideBarMarkdownContainer: View {
    let text: String
    let style: SideBarMarkdownStyle
    let youtubeTranscriptContext: SideBarYouTubeTranscriptContext?
    let renderingContext: SideBarMarkdownRenderingContext

    init(
        text: String,
        style: SideBarMarkdownStyle = .default,
        youtubeTranscriptContext: SideBarYouTubeTranscriptContext? = nil,
        renderingContext: SideBarMarkdownRenderingContext = .standard
    ) {
        self.text = text
        self.style = style
        self.youtubeTranscriptContext = youtubeTranscriptContext
        self.renderingContext = renderingContext
    }

    var body: some View {
        SideBarMarkdown(
            text: text,
            style: style,
            youtubeTranscriptContext: youtubeTranscriptContext,
            renderingContext: renderingContext
        )
            .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth, alignment: .leading)
            .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
            .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct SideBarMarkdown: View, Equatable {
    let text: String
    let style: SideBarMarkdownStyle
    let youtubeTranscriptContext: SideBarYouTubeTranscriptContext?
    let renderingContext: SideBarMarkdownRenderingContext

    init(
        text: String,
        style: SideBarMarkdownStyle = .default,
        youtubeTranscriptContext: SideBarYouTubeTranscriptContext? = nil,
        renderingContext: SideBarMarkdownRenderingContext = .standard
    ) {
        self.text = text
        self.style = style
        self.youtubeTranscriptContext = youtubeTranscriptContext
        self.renderingContext = renderingContext
    }

    static func == (lhs: SideBarMarkdown, rhs: SideBarMarkdown) -> Bool {
        // Transcript button state (queued/processing) is driven by external view model state.
        // Force re-render whenever transcript context is present so status changes are reflected.
        if lhs.youtubeTranscriptContext != nil || rhs.youtubeTranscriptContext != nil {
            return false
        }
        return lhs.text == rhs.text
            && lhs.style == rhs.style
            && lhs.renderingContext == rhs.renderingContext
    }

    var body: some View {
        #if canImport(MarkdownUI)
        let displayText = youtubeTranscriptContext == nil
            ? text
            : MarkdownRendering.stripWebsiteTranscriptArtifacts(text)
        let blocks = renderingContext == .website
            ? MarkdownRendering.normalizedWebsiteBlocks(from: displayText)
            : MarkdownRendering.normalizedBlocks(from: displayText)
        if blocks.isEmpty {
            styledMarkdown(displayText)
        } else {
            VStack(alignment: .leading, spacing: SideBarMarkdownLayout.blockSpacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .markdown(let content):
                        styledMarkdown(content)
                    case .gallery(let gallery):
                        MarkdownGalleryView(gallery: gallery)
                    case .youtube(let embed):
                        SideBarYouTubeEmbedBlock(
                            embed: embed,
                            text: text,
                            context: youtubeTranscriptContext
                        )
                    case .suppressedSVG:
                        SideBarSuppressedSVGBlock()
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

struct SideBarYouTubeTranscriptContext {
    let websiteId: String
    let isTranscriptPending: (String) -> Bool
    let requestTranscript: (String, String) async -> Void
}

private struct SideBarYouTubeEmbedBlock: View {
    let embed: MarkdownRendering.MarkdownYouTubeEmbed
    let text: String
    let context: SideBarYouTubeTranscriptContext?
    @State private var isPlayerLoaded = false

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ZStack {
                YouTubePlayerView(url: embed.embedURL) { isLoaded in
                    isPlayerLoaded = isLoaded
                }
                .opacity(isPlayerLoaded ? 1 : 0.001)

                if !isPlayerLoaded {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignTokens.Colors.muted)
                    ProgressView("Loading video…")
                        .font(.footnote)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if isPlayerLoaded, let context, shouldShowTranscriptButton(context: context) {
                Button {
                    Task {
                        await context.requestTranscript(context.websiteId, embed.sourceURL)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isQueuedOrProcessing(context: context) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isQueuedOrProcessing(context: context) ? "Transcribing" : "Get Transcript")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isQueuedOrProcessing(context: context))
                .frame(maxWidth: 420)
            }
        }
    }

    private func shouldShowTranscriptButton(context: SideBarYouTubeTranscriptContext) -> Bool {
        !text.contains("<!-- YOUTUBE_TRANSCRIPT:\(embed.videoId) -->")
    }

    private func isQueuedOrProcessing(context: SideBarYouTubeTranscriptContext) -> Bool {
        context.isTranscriptPending(embed.videoId)
    }
}

private struct SideBarSuppressedSVGBlock: View {
    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "photo")
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .font(.body.weight(.semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("SVG diagram omitted")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("Open this page in the web app to view the full diagram.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.muted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }
}
