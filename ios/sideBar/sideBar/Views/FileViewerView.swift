import SwiftUI
import PDFKit
import AVKit
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

    public init(state: FileViewerState) {
        self.state = state
    }

    public var body: some View {
        Group {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var markdownView: some View {
        ScrollView {
            MarkdownView(text: state.text ?? "")
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var textView: some View {
        ScrollView {
            Text(state.text ?? "No preview available.")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
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
            PDFKitView(url: url)
        } else {
            PlaceholderView(title: "PDF preview unavailable")
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let url = state.fileURL {
            ScrollView([.vertical, .horizontal]) {
                PlatformImageView(url: url)
            }
        } else {
            PlaceholderView(title: "Image preview unavailable")
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        if let url = state.fileURL {
            VStack(spacing: 12) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: state.kind == .audio ? 72 : 360)
                if state.kind == .audio {
                    Text("Audio playback")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
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

private struct MarkdownView: View {
    let text: String

    var body: some View {
        #if canImport(MarkdownUI)
        Markdown(text)
        #else
        Text(text)
        #endif
    }
}

#if os(macOS)
private struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}

private struct PlatformImageView: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(20)
        } else {
            PlaceholderView(title: "Unable to load image")
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}
#else
private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}

private struct PlatformImageView: View {
    let url: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(20)
        } else {
            PlaceholderView(title: "Unable to load image")
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
#endif
