import SwiftUI
import UniformTypeIdentifiers

struct VideoPlayerContainer: View {
    let url: URL
    @State private var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(DesignTokens.Spacing.lg)
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

struct MarkdownView: View {
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
    private var containerSize: CGSize = .zero
    private var animateNextFit = false

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
        containerSize = .zero
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
        _ = applyScaleForCurrentPage()
    }

    func zoomOut() {
        guard let pdfView else { return }
        guard pdfView.maxScaleFactor > 0 else { return }
        zoomMultiplier = max(zoomMultiplier / 1.2, 0.2)
        _ = applyScaleForCurrentPage()
    }

    func setFitMode(_ mode: FitMode) {
        fitMode = mode
        zoomMultiplier = 1
        scheduleFitAndRefresh()
    }

    func scheduleFitAndRefresh() {
        scheduleFitAndRefresh(animated: true)
    }

    private func scheduleFitAndRefresh(animated: Bool) {
        fitRetryWorkItem?.cancel()
        animateNextFit = animated
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyFitWithRetry(attempt: 0)
        }
        fitRetryWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func updateContainerSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if abs(containerSize.width - size.width) < 0.5, abs(containerSize.height - size.height) < 0.5 {
            return
        }
        containerSize = size
        scheduleFitAndRefresh(animated: false)
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
        if attempt > 0 {
            animateNextFit = false
        }
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
        applyScale(clamped, animated: animateNextFit)
        animateNextFit = false
        scale = clamped
        return true
    }

    private func applyScale(_ scale: CGFloat, animated: Bool) {
        guard let pdfView else { return }
        guard animated else {
            pdfView.scaleFactor = scale
            return
        }
        #if os(macOS)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pdfView.animator().scaleFactor = scale
        }
        #else
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            pdfView.scaleFactor = scale
        }
        #endif
    }

    private func baseScaleForCurrentPage() -> CGFloat? {
        guard let pdfView,
              let page = pdfView.currentPage else { return nil }
        let pageBounds = page.bounds(for: .cropBox)
        let size = containerSize.width > 0 ? containerSize : pdfView.bounds.size
        guard pageBounds.width > 0, pageBounds.height > 0, size.width > 0, size.height > 0 else {
            return nil
        }
        let widthScale = size.width / pageBounds.width
        let heightScale = size.height / pageBounds.height
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
struct PDFViewerContainer: View {
    let url: URL
    let controller: PDFViewerController

    var body: some View {
        GeometryReader { proxy in
            PDFViewer(url: url, controller: controller)
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
struct PDFViewerContainer: View {
    let url: URL
    let controller: PDFViewerController

    var body: some View {
        GeometryReader { proxy in
            PDFViewer(url: url, controller: controller)
                .onChange(of: proxy.size) { _, _ in
                    controller.updateContainerSize(proxy.size)
                }
                .onAppear {
                    controller.updateContainerSize(proxy.size)
                }
        }
    }
}

struct PDFViewer: UIViewRepresentable {
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

struct PDFKitView: UIViewRepresentable {
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
