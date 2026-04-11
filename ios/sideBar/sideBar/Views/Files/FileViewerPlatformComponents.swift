import PDFKit
import AVKit
#if os(macOS)
import QuickLook
import QuickLookUI
#elseif canImport(QuickLook)
import QuickLook
#endif
import SwiftUI

#if os(macOS)
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.updatesNowPlayingInfoCenter = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct PDFViewerContainer: View {
    let url: URL
    let controller: PDFViewerController

    var body: some View {
        GeometryReader { proxy in
            PDFViewer(url: url, controller: controller)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .onChange(of: proxy.size) { _, _ in
                    controller.updateContainerSize(proxy.size)
                }
                .onAppear {
                    controller.updateContainerSize(proxy.size)
                }
        }
    }
}

struct PDFViewer: NSViewRepresentable {
    let url: URL
    let controller: PDFViewerController

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = NSColor.appBackground
        context.coordinator.loadDocument(into: view, url: url)
        controller.attach(pdfView: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.loadDocument(into: nsView, url: url)
        controller.attach(pdfView: nsView)
        controller.scheduleFitAndRefresh()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var document: PDFDocument?
        private var documentURL: URL?

        func loadDocument(into view: PDFView, url: URL) {
            guard documentURL != url else { return }
            documentURL = url
            let doc = PDFDocument(url: url)
            document = doc
            view.document = doc
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = NSColor.appBackground
        context.coordinator.loadDocument(into: view, url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.loadDocument(into: nsView, url: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var document: PDFDocument?
        private var documentURL: URL?

        func loadDocument(into view: PDFView, url: URL) {
            guard documentURL != url else { return }
            documentURL = url
            let doc = PDFDocument(url: url)
            document = doc
            view.document = doc
        }
    }
}

struct PlatformImageView: View {
    let url: URL
    let size: CGSize

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size.width, maxHeight: size.height)
                .padding(DesignTokens.Spacing.sm)
        } else {
            PlaceholderView(title: "Unable to load image")
        }
    }
}

struct QuickLookPreview: NSViewRepresentable {
    typealias NSViewType = NSView
    let url: URL

    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView()
        }
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewView = nsView as? QLPreviewView else { return }
        previewView.previewItem = url as QLPreviewItem
    }
}
#else
struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

struct PDFViewerContainer: View {
    let url: URL
    let controller: PDFViewerController

    var body: some View {
        GeometryReader { proxy in
            PDFViewer(url: url, controller: controller)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .onChange(of: proxy.size) { _, _ in
                    PDFResizeDebugTrace.log(
                        "PDFViewerContainer.sizeChanged",
                        details: "size=\(PDFResizeDebugTrace.describe(proxy.size)) url=\(url.lastPathComponent)"
                    )
                    controller.updateContainerSize(proxy.size)
                }
                .onAppear {
                    PDFResizeDebugTrace.log(
                        "PDFViewerContainer.appear",
                        details: "size=\(PDFResizeDebugTrace.describe(proxy.size)) url=\(url.lastPathComponent)"
                    )
                    controller.updateContainerSize(proxy.size)
                }
        }
    }
}

final class ClippedPDFHostView: UIView {
    let pdfView = PDFView()
    private var lastLayoutSummary: String?

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        pdfView.clipsToBounds = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard PDFResizeDebugTrace.isEnabled else { return }

        let summary = [
            "host=\(PDFResizeDebugTrace.describe(bounds))",
            "pdf=\(PDFResizeDebugTrace.describe(pdfView.bounds))",
            describeScrollViewState()
        ].joined(separator: " ")

        guard summary != lastLayoutSummary else { return }
        lastLayoutSummary = summary
        PDFResizeDebugTrace.log("ClippedPDFHostView.layoutSubviews", details: summary)
    }

    private func describeScrollViewState() -> String {
        guard let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else {
            return "scroll=nil"
        }
        let documentView = scrollView.subviews.first
        return [
            "scrollClass=\(NSStringFromClass(type(of: scrollView)))",
            "scrollBounds=\(PDFResizeDebugTrace.describe(scrollView.bounds))",
            "contentSize=\(PDFResizeDebugTrace.describe(scrollView.contentSize))",
            "contentOffset=\(PDFResizeDebugTrace.describe(scrollView.contentOffset))",
            "zoomScale=\(PDFResizeDebugTrace.rounded(scrollView.zoomScale))",
            "docClass=\(documentView.map { NSStringFromClass(type(of: $0)) } ?? "nil")",
            "docFrame=\(documentView.map { PDFResizeDebugTrace.describe($0.frame) } ?? "nil")"
        ].joined(separator: " ")
    }
}

struct PDFViewer: UIViewRepresentable {
    let url: URL
    let controller: PDFViewerController

    func makeUIView(context: Context) -> ClippedPDFHostView {
        let hostView = ClippedPDFHostView()
        hostView.pdfView.backgroundColor = UIColor.systemBackground
        context.coordinator.loadDocument(into: hostView.pdfView, url: url)
        controller.attach(pdfView: hostView.pdfView)
        return hostView
    }

    func updateUIView(_ uiView: ClippedPDFHostView, context: Context) {
        context.coordinator.loadDocument(into: uiView.pdfView, url: url)
        controller.attach(pdfView: uiView.pdfView)
        controller.scheduleFitAndRefresh()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var document: PDFDocument?
        private var documentURL: URL?

        func loadDocument(into view: PDFView, url: URL) {
            guard documentURL != url else { return }
            documentURL = url
            let doc = PDFDocument(url: url)
            document = doc
            view.document = doc
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> ClippedPDFHostView {
        let hostView = ClippedPDFHostView()
        hostView.pdfView.autoScales = true
        hostView.pdfView.backgroundColor = UIColor.systemBackground
        context.coordinator.loadDocument(into: hostView.pdfView, url: url)
        return hostView
    }

    func updateUIView(_ uiView: ClippedPDFHostView, context: Context) {
        context.coordinator.loadDocument(into: uiView.pdfView, url: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var document: PDFDocument?
        private var documentURL: URL?

        func loadDocument(into view: PDFView, url: URL) {
            guard documentURL != url else { return }
            documentURL = url
            let doc = PDFDocument(url: url)
            document = doc
            view.document = doc
        }
    }
}

struct PlatformImageView: View {
    let url: URL
    let size: CGSize

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size.width, maxHeight: size.height)
                .padding(DesignTokens.Spacing.sm)
        } else {
            PlaceholderView(title: "Unable to load image")
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
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
