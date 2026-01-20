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
    public let state: FileViewerState
    public let pdfController: PDFViewerController?

    public init(state: FileViewerState, pdfController: PDFViewerController? = nil) {
        self.state = state
        self.pdfController = pdfController
    }

    public var body: some View {
        Group {
            if let embedURL = state.youtubeEmbedURL {
                VStack(spacing: 0) {
                    YouTubePlayerView(url: embedURL)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
                        .padding(.top, SideBarMarkdownLayout.verticalPadding)
                    constrainedContentView
                }
            } else {
                contentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(DesignTokens.Typography.monoBody)
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
                    .padding(DesignTokens.Spacing.lg)
            } else {
                VideoPlayerContainer(url: url)
            }
        } else {
            PlaceholderView(title: "Media preview unavailable")
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
