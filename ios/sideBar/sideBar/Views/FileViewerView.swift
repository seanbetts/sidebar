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
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
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
                PDFViewer(url: url, controller: pdfController)
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
                    .padding(20)
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

private struct VideoPlayerContainer: View {
    let url: URL
    @State private var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(20)
            .padding(.top, SideBarMarkdownLayout.verticalPadding)
            .task {
                await updateAspectRatio()
            }
    }

    private func updateAspectRatio() async {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.load(.tracks)
            guard let track = tracks.first(where: { $0.mediaType == .video }) else { return }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            guard width > 0, height > 0 else { return }
            let ratio = width / height
            await MainActor.run {
                aspectRatio = ratio
            }
        } catch {
            return
        }
    }
}

private struct MarkdownView: View {
    let text: String

    var body: some View {
        #if canImport(MarkdownUI)
        SideBarMarkdownContainer(text: text)
        #else
        Text(text)
        #endif
    }
}

public final class PDFViewerController: ObservableObject {
    enum FitMode: String, CaseIterable {
        case auto
        case width
        case height
    }

    @Published private(set) var currentPage: Int = 1
    @Published private(set) var pageCount: Int = 1
    @Published private(set) var canPrev: Bool = false
    @Published private(set) var canNext: Bool = false
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var fitMode: FitMode = .height
    @Published private(set) var zoomMultiplier: CGFloat = 1

    fileprivate weak var pdfView: PDFView?
    private var observers: [NSObjectProtocol] = []
    private var fitRetryWorkItem: DispatchWorkItem?

    deinit {
        cleanupObservers()
        fitRetryWorkItem?.cancel()
    }

    func attach(pdfView: PDFView) {
        if self.pdfView === pdfView { return }
        self.pdfView = pdfView
        configure(pdfView: pdfView)
        observe(pdfView: pdfView)
        scheduleFitAndRefresh()
    }

    func reset() {
        currentPage = 1
        pageCount = 1
        canPrev = false
        canNext = false
        scale = 1
        fitMode = .height
        zoomMultiplier = 1
    }

    func goToPreviousPage() {
        pdfView?.goToPreviousPage(nil)
    }

    func goToNextPage() {
        pdfView?.goToNextPage(nil)
    }

    func zoomIn() {
        guard let pdfView else { return }
        guard pdfView.maxScaleFactor > 0 else { return }
        zoomMultiplier = min(zoomMultiplier * 1.2, 6)
        applyScaleForCurrentPage()
    }

    func zoomOut() {
        guard let pdfView else { return }
        guard pdfView.maxScaleFactor > 0 else { return }
        zoomMultiplier = max(zoomMultiplier / 1.2, 0.2)
        applyScaleForCurrentPage()
    }

    func setFitMode(_ mode: FitMode) {
        fitMode = mode
        zoomMultiplier = 1
        scheduleFitAndRefresh()
    }

    func scheduleFitAndRefresh() {
        fitRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyFitWithRetry(attempt: 0)
        }
        fitRetryWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func reapplyZoomForCurrentPage() {
        fitRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyZoomWithRetry(attempt: 0)
        }
        fitRetryWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func configure(pdfView: PDFView) {
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(true, withViewOptions: nil)
        let baseScale = pdfView.scaleFactorForSizeToFit
        if baseScale > 0 {
            pdfView.minScaleFactor = max(baseScale * 0.5, 0.1)
            pdfView.maxScaleFactor = max(baseScale * 4.0, pdfView.minScaleFactor)
        }
        scheduleFitAndRefresh()
    }

    private func observe(pdfView: PDFView) {
        cleanupObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            self?.reapplyZoomForCurrentPage()
        })
        observers.append(center.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            self?.refreshState()
        })
        observers.append(center.addObserver(forName: .PDFViewDocumentChanged, object: pdfView, queue: .main) { [weak self] _ in
            self?.scheduleFitAndRefresh()
        })
    }

    private func cleanupObservers() {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
        observers = []
    }

    private func refreshState() {
        guard let pdfView else { return }
        let count = pdfView.document?.pageCount ?? 1
        pageCount = max(count, 1)
        if let current = pdfView.currentPage,
           let document = pdfView.document {
            currentPage = max(document.index(for: current) + 1, 1)
        } else {
            currentPage = 1
        }
        canPrev = currentPage > 1
        canNext = currentPage < pageCount
        scale = pdfView.scaleFactor
    }

    private func applyFitWithRetry(attempt: Int) {
        guard applyScaleForCurrentPage() else {
            if attempt < 5 {
                let delay = 0.1 * Double(attempt + 1)
                let workItem = DispatchWorkItem { [weak self] in
                    self?.applyFitWithRetry(attempt: attempt + 1)
                }
                fitRetryWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
            return
        }
        refreshState()
    }

    private func applyZoomWithRetry(attempt: Int) {
        guard applyScaleForCurrentPage() else {
            if attempt < 5 {
                let delay = 0.1 * Double(attempt + 1)
                let workItem = DispatchWorkItem { [weak self] in
                    self?.applyZoomWithRetry(attempt: attempt + 1)
                }
                fitRetryWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
            return
        }
        refreshState()
    }

    private func applyScaleForCurrentPage() -> Bool {
        guard let pdfView,
              let page = pdfView.currentPage else { return false }
        let pageBounds = page.bounds(for: .cropBox)
        let containerSize = pdfView.bounds.size
        guard pageBounds.width > 0, pageBounds.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return false
        }
        guard let baseScale = baseScaleForCurrentPage() else { return false }
        let targetScale = baseScale * zoomMultiplier
        let minScale = max(pdfView.minScaleFactor, 0.1)
        let maxScale = max(pdfView.maxScaleFactor, minScale)
        let clamped = min(max(targetScale, minScale), maxScale)
        guard clamped.isFinite, clamped > 0 else { return false }
        pdfView.scaleFactor = clamped
        scale = clamped
        return true
    }

    private func baseScaleForCurrentPage() -> CGFloat? {
        guard let pdfView,
              let page = pdfView.currentPage else { return nil }
        let pageBounds = page.bounds(for: .cropBox)
        let containerSize = pdfView.bounds.size
        guard pageBounds.width > 0, pageBounds.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return nil
        }
        let widthScale = containerSize.width / pageBounds.width
        let heightScale = containerSize.height / pageBounds.height
        let baseScale: CGFloat
        switch fitMode {
        case .auto:
            baseScale = min(widthScale, heightScale)
        case .width:
            baseScale = widthScale
        case .height:
            baseScale = min(heightScale, widthScale)
        }
        guard baseScale.isFinite, baseScale > 0 else { return nil }
        return baseScale
    }
}

#if os(macOS)
private struct PDFViewer: NSViewRepresentable {
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

private struct PDFKitView: NSViewRepresentable {
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

private struct PlatformImageView: View {
    let url: URL
    let size: CGSize

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size.width, maxHeight: size.height)
                .padding(12)
        } else {
            PlaceholderView(title: "Unable to load image")
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
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
private struct PDFViewer: UIViewRepresentable {
    let url: URL
    let controller: PDFViewerController

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = UIColor.systemBackground
        context.coordinator.loadDocument(into: view, url: url)
        controller.attach(pdfView: view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.loadDocument(into: uiView, url: url)
        controller.attach(pdfView: uiView)
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

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = UIColor.systemBackground
        context.coordinator.loadDocument(into: view, url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.loadDocument(into: uiView, url: url)
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

private struct PlatformImageView: View {
    let url: URL
    let size: CGSize

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size.width, maxHeight: size.height)
                .padding(12)
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
