#if os(iOS)
import Combine
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class FileViewerMountedIOSTests: XCTestCase {
    func testPlatformImageFileLoaderDownsamplesLargeImage() async throws {
        let url = try makeTemporaryPNGURL(size: CGSize(width: 1200, height: 800))

        let loadedImage = await PlatformImageFileLoader.loadImage(url: url, maxPixelSize: 240)
        let image = try XCTUnwrap(loadedImage)

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 240)
    }

    func testMountedPDFViewerShrinksWhenParentWorkspaceNarrows() throws {
        let url = try makeTemporaryPDFURL()
        let widthModel = FileViewerWidthModel(width: 960)
        let pdfController = PDFViewerController()
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.first as? UIWindowScene
        )
        let controller = UIHostingController(
            rootView: AnyView(
                FileViewerResizeHarness(
                    widthModel: widthModel,
                    state: FileViewerState(
                        title: "Sample",
                        kind: .pdf,
                        text: nil,
                        fileURL: url,
                        spreadsheet: nil,
                        youtubeEmbedURL: nil
                    ),
                    pdfController: pdfController
                )
            )
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 960, height: 900)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        layout(hostingController: controller)
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }

        let initialHost = try XCTUnwrap(findPDFHostView(in: controller.view))
        let initialWidth = initialHost.bounds.width
        let initialScale = try XCTUnwrap(findPDFView(in: controller.view)).scaleFactor

        widthModel.width = 560
        layout(hostingController: controller)

        let narrowedHost = try XCTUnwrap(findPDFHostView(in: controller.view))
        let pdfView = try XCTUnwrap(findPDFView(in: controller.view))
        let scrollView = try XCTUnwrap(findPDFScrollView(in: pdfView))
        let documentView = try XCTUnwrap(scrollView.subviews.first)
        let narrowedWidth = narrowedHost.bounds.width

        XCTAssertLessThan(narrowedHost.bounds.width, initialWidth)
        XCTAssertEqual(narrowedHost.bounds.width, widthModel.width, accuracy: 1)
        XCTAssertEqual(pdfView.bounds.width, narrowedHost.bounds.width, accuracy: 1)
        XCTAssertLessThan(pdfView.scaleFactor, initialScale)
        XCTAssertTrue(pdfView.clipsToBounds)
        XCTAssertLessThanOrEqual(documentView.frame.width, narrowedHost.bounds.width + 1)

        widthModel.width = 820
        layout(hostingController: controller)

        let expandedHost = try XCTUnwrap(findPDFHostView(in: controller.view))
        let expandedPDFView = try XCTUnwrap(findPDFView(in: controller.view))
        let expandedScrollView = try XCTUnwrap(findPDFScrollView(in: expandedPDFView))
        let expandedDocumentView = try XCTUnwrap(expandedScrollView.subviews.first)

        XCTAssertGreaterThan(expandedHost.bounds.width, narrowedWidth)
        XCTAssertEqual(expandedPDFView.bounds.width, expandedHost.bounds.width, accuracy: 1)
        XCTAssertLessThanOrEqual(expandedDocumentView.frame.width, expandedHost.bounds.width + 1)
    }

    private func layout(hostingController: UIHostingController<AnyView>) {
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func makeTemporaryPDFURL() throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 200))
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            let title = "PDF"
            title.draw(
                at: CGPoint(x: 24, y: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
            )
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeTemporaryPNGURL(size: CGSize) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: size)
        let data = renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func findPDFView(in view: UIView) -> PDFView? {
        if let pdfView = view as? PDFView {
            return pdfView
        }

        for subview in view.subviews {
            if let pdfView = findPDFView(in: subview) {
                return pdfView
            }
        }

        return nil
    }

    private func findPDFScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findPDFScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }

    private func findPDFHostView(in view: UIView) -> ClippedPDFHostView? {
        if let hostView = view as? ClippedPDFHostView {
            return hostView
        }

        for subview in view.subviews {
            if let hostView = findPDFHostView(in: subview) {
                return hostView
            }
        }

        return nil
    }
}

@MainActor
private final class FileViewerWidthModel: ObservableObject {
    @Published var width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }
}

@MainActor
private struct FileViewerResizeHarness: View {
    @ObservedObject var widthModel: FileViewerWidthModel
    let state: FileViewerState
    let pdfController: PDFViewerController

    var body: some View {
        FileViewerView(state: state, pdfController: pdfController)
            .frame(width: widthModel.width, height: 900)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
