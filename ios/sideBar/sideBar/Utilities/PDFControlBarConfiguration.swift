import CoreGraphics
import Foundation

struct PDFControlBarConfiguration {
    let canGoToPreviousPage: Bool
    let canGoToNextPage: Bool
    let pageLabel: String
    let zoomLabel: String
    let fitMode: PDFViewerController.FitMode
    let isEnabled: Bool
    let onGoToPreviousPage: @MainActor @Sendable () -> Void
    let onGoToNextPage: @MainActor @Sendable () -> Void
    let onZoomOut: @MainActor @Sendable () -> Void
    let onZoomIn: @MainActor @Sendable () -> Void
    let onSetFitMode: @MainActor @Sendable (PDFViewerController.FitMode) -> Void

    static let disabled = PDFControlBarConfiguration(
        canGoToPreviousPage: false,
        canGoToNextPage: false,
        pageLabel: "1 / 1",
        zoomLabel: "100%",
        fitMode: .height,
        isEnabled: false,
        onGoToPreviousPage: {},
        onGoToNextPage: {},
        onZoomOut: {},
        onZoomIn: {},
        onSetFitMode: { _ in }
    )
}

extension PDFViewerController {
    var controlBarConfiguration: PDFControlBarConfiguration {
        PDFControlBarConfiguration(
            canGoToPreviousPage: canPrev,
            canGoToNextPage: canNext,
            pageLabel: "\(currentPage) / \(max(pageCount, 1))",
            zoomLabel: "\(Int(round(zoomMultiplier * 100)))%",
            fitMode: fitMode,
            isEnabled: pageCount > 0,
            onGoToPreviousPage: { [weak self] in self?.goToPreviousPage() },
            onGoToNextPage: { [weak self] in self?.goToNextPage() },
            onZoomOut: { [weak self] in self?.zoomOut() },
            onZoomIn: { [weak self] in self?.zoomIn() },
            onSetFitMode: { [weak self] mode in self?.setFitMode(mode) }
        )
    }
}
