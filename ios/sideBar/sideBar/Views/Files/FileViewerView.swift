import SwiftUI
import PDFKit
import AVKit
import AVFoundation
import Combine
#if canImport(MarkdownUI)
import MarkdownUI
#endif

#if os(macOS)
import QuickLookUI
#else
import QuickLook
#endif

public struct FileViewerView: View {
    enum VideoTranscriptPresentation: Equatable {
        case plainText
    }

    static let videoTranscriptPresentation: VideoTranscriptPresentation = .plainText

    public let state: FileViewerState
    public let pdfController: PDFViewerController?
    @Environment(\.openURL) private var openURL

    public init(state: FileViewerState, pdfController: PDFViewerController? = nil) {
        self.state = state
        self.pdfController = pdfController
    }

    public var body: some View {
        Group {
            if let embedURL = state.youtubeEmbedURL, Self.shouldShowYouTubeEmbed(for: state) {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    YouTubePlayerView(url: embedURL)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
                        .padding(.top, SideBarMarkdownLayout.verticalPadding)
                    Button {
                        openURL(YouTubeURLPolicy.preferredExternalURL(from: embedURL))
                    } label: {
                        Label("Open in YouTube", systemImage: "arrow.up.right.square")
                            .appFont(.footnoteSemibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth)
                    .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
                    constrainedContentView
                }
            } else {
                contentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func shouldShowYouTubeEmbed(for state: FileViewerState) -> Bool {
        guard state.youtubeEmbedURL != nil else {
            return false
        }
        return state.kind != .video
    }

    @ViewBuilder
    private var contentView: some View {
        switch state.kind {
        case .markdown:
            markdownView
        case .text, .json:
            textView
        case .spreadsheet:
            spreadsheetView
        case .pdf:
            pdfView
        case .image:
            imageView
        case .audio, .video:
            mediaView
        case .quickLook:
            quickLookView
        }
    }

    private var markdownView: some View {
        ScrollView {
            MarkdownView(text: state.text ?? "")
        }
    }

    private var textView: some View {
        ScrollView {
            Text(state.text ?? "No preview available.")
                .appFont(.monoBody)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.lg)
        }
    }

    private var constrainedContentView: some View {
        contentView
            .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var spreadsheetView: some View {
        if let spreadsheet = state.spreadsheet {
            SpreadsheetViewer(payload: spreadsheet)
        } else {
            PlaceholderView(title: "No spreadsheet preview available")
        }
    }

    @ViewBuilder
    private var pdfView: some View {
        if let url = state.fileURL {
            if let pdfController {
                PDFViewerContainer(url: url, controller: pdfController)
                    .overlay(alignment: .topTrailing) {
                        PdfViewerFloatingControls(controller: pdfController)
                            .padding(.top, DesignTokens.Spacing.sm)
                            .padding(.trailing, DesignTokens.Spacing.md)
                    }
            } else {
                PDFKitView(url: url)
            }
        } else {
            PlaceholderView(title: "PDF preview unavailable")
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let url = state.fileURL {
            GeometryReader { proxy in
                PlatformImageView(url: url, size: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            PlaceholderView(title: "Image preview unavailable")
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        if let url = state.fileURL {
            if state.kind == .audio {
                AudioPlayerView(url: url)
                    .id(url)
                    .padding(DesignTokens.Spacing.lg)
            } else {
                if let transcript = Self.videoTranscript(for: state) {
                    ScrollView {
                        VStack(spacing: DesignTokens.Spacing.lg) {
                            VideoPlayerContainer(url: url)
                                .id(url)
                            videoTranscriptView(text: transcript)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    VideoPlayerContainer(url: url)
                        .id(url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        } else {
            PlaceholderView(title: "Media preview unavailable")
        }
    }

    static func videoTranscript(for state: FileViewerState) -> String? {
        guard state.kind == .video else { return nil }
        let transcript = (state.text ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return transcript.isEmpty ? nil : transcript
    }

    @ViewBuilder
    private func videoTranscriptView(text: String) -> some View {
        switch Self.videoTranscriptPresentation {
        case .plainText:
            Text(text)
                .appFont(.body)
                .textSelection(.enabled)
                .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth, alignment: .leading)
                .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
                .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var quickLookView: some View {
        if let url = state.fileURL {
            QuickLookPreview(url: url)
        } else {
            PlaceholderView(title: "Preview unavailable")
        }
    }
}
