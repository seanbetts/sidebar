import SwiftUI

enum PDFControlBarChrome {
    static let entryControlChromeStyle: HeaderActionControlChromeStyle = .glass
    static let entrySymbolPointSize: CGFloat = HeaderActionControlMetrics.symbolPointSize
    static let entryControlWidth: CGFloat = HeaderActionControlMetrics.chromeWidth
    static let entryControlHeight: CGFloat = HeaderActionControlMetrics.chromeHeight

    static func cornerRadius(for barHeight: CGFloat) -> CGFloat {
        _ = barHeight
        return DesignTokens.Radius.sm
    }
}

struct PDFControlBar: View {
    let configuration: PDFControlBarConfiguration

    var body: some View {
        HeaderActionMenuControl(
            systemName: "doc.viewfinder",
            accessibilityLabel: "PDF controls",
            chromeStyle: PDFControlBarChrome.entryControlChromeStyle
        ) {
            PDFControlBarMenuContent(configuration: configuration)
        }
        .disabled(!configuration.isEnabled)
        .accessibilityIdentifier("pdf-control-bar")
    }
}

struct PDFControlBarMenuContent: View {
    let configuration: PDFControlBarConfiguration

    var body: some View {
        Section("Page") {
            Button {
                configuration.onGoToPreviousPage()
            } label: {
                Label("Previous page", systemImage: "chevron.left")
            }
            .disabled(!configuration.canGoToPreviousPage)

            Button {
                configuration.onGoToNextPage()
            } label: {
                Label("Next page", systemImage: "chevron.right")
            }
            .disabled(!configuration.canGoToNextPage)
        }

        Section("Zoom") {
            Button {
                configuration.onZoomOut()
            } label: {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
            }

            Button {
                configuration.onZoomIn()
            } label: {
                Label("Zoom in", systemImage: "plus.magnifyingglass")
            }

            Text("Zoom: \(configuration.zoomLabel)")
        }

        Section("Fit") {
            fitModeButton("Fit to height", systemImage: "distribute.vertical", mode: .height)
            fitModeButton("Fit to width", systemImage: "distribute.horizontal", mode: .width)
        }

        Section("Status") {
            Text("Page \(configuration.pageLabel)")
        }
    }

    @ViewBuilder
    private func fitModeButton(
        _ title: String,
        systemImage: String,
        mode: PDFViewerController.FitMode
    ) -> some View {
        Button {
            configuration.onSetFitMode(mode)
        } label: {
            if configuration.fitMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

struct PDFControlPopoverContent: View {
    let configuration: PDFControlBarConfiguration
    var onDismissRequested: @MainActor @Sendable () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            sectionTitle("Page")
            HStack(spacing: DesignTokens.Spacing.xs) {
                HeaderActionButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Previous page",
                    action: perform(configuration.onGoToPreviousPage),
                    isDisabled: !configuration.canGoToPreviousPage,
                    chromeStyle: .glass
                )

                Spacer(minLength: DesignTokens.Spacing.xs)

                Text(configuration.pageLabel)
                    .appFont(.labelMd)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: DesignTokens.Spacing.xs)

                HeaderActionButton(
                    systemName: "chevron.right",
                    accessibilityLabel: "Next page",
                    action: perform(configuration.onGoToNextPage),
                    isDisabled: !configuration.canGoToNextPage,
                    chromeStyle: .glass
                )
            }

            Divider()

            sectionTitle("Zoom")
            HStack(spacing: DesignTokens.Spacing.xs) {
                HeaderActionButton(
                    systemName: "minus.magnifyingglass",
                    accessibilityLabel: "Zoom out",
                    action: perform(configuration.onZoomOut),
                    chromeStyle: .glass
                )

                Spacer(minLength: DesignTokens.Spacing.xs)

                Text(configuration.zoomLabel)
                    .appFont(.labelMd)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: DesignTokens.Spacing.xs)

                HeaderActionButton(
                    systemName: "plus.magnifyingglass",
                    accessibilityLabel: "Zoom in",
                    action: perform(configuration.onZoomIn),
                    chromeStyle: .glass
                )
            }

            Divider()

            sectionTitle("Fit")
            HStack(spacing: DesignTokens.Spacing.xs) {
                fitModeChip("Fit to width", mode: .width)
                fitModeChip("Fit to height", mode: .height)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pdf-control-popover-content")
    }

    private func perform(_ action: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        {
            action()
            onDismissRequested()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .appFont(.captionSemibold)
            .foregroundStyle(.secondary)
    }

    private func fitModeChip(_ title: String, mode: PDFViewerController.FitMode) -> some View {
        Button {
            configuration.onSetFitMode(mode)
            onDismissRequested()
        } label: {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                if configuration.fitMode == mode {
                    Image(systemName: "checkmark")
                        .appFont(.labelMd)
                }
                Text(title)
                    .appFont(.labelMd)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxsPlus)
            .glassChrome(.pill)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
