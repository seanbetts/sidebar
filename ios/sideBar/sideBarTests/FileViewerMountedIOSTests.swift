#if os(iOS)
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class FileViewerMountedIOSTests: XCTestCase {
    func testMountedPDFViewerClipsToBoundsWithinWorkspace() throws {
        let url = try makeTemporaryPDFURL()
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.first as? UIWindowScene
        )
        let controller = UIHostingController(
            rootView: AnyView(
                FileViewerView(
                    state: FileViewerState(
                        title: "Sample",
                        kind: .pdf,
                        text: nil,
                        fileURL: url,
                        spreadsheet: nil,
                        youtubeEmbedURL: nil
                    ),
                    pdfController: PDFViewerController()
                )
            )
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 900)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }

        let pdfView = try XCTUnwrap(findPDFView(in: controller.view))

        XCTAssertTrue(pdfView.clipsToBounds)
    }

    private func makeTemporaryPDFURL() throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
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
}
#endif
