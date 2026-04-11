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
        HStack(spacing: DesignTokens.Spacing.sm) {
            pageGroup
            groupDivider
            zoomGroup
            groupDivider
            fitGroup
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pdf-control-popover-content")
    }

    private func perform(_ action: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        {
            action()
            onDismissRequested()
        }
    }

    private var pageGroup: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            compactButton(
                systemName: "chevron.left",
                accessibilityLabel: "Previous page",
                action: perform(configuration.onGoToPreviousPage),
                isDisabled: !configuration.canGoToPreviousPage
            )

            Text(configuration.pageLabel)
                .appFont(.labelMd)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(minWidth: 48)

            compactButton(
                systemName: "chevron.right",
                accessibilityLabel: "Next page",
                action: perform(configuration.onGoToNextPage),
                isDisabled: !configuration.canGoToNextPage
            )
        }
    }

    private var zoomGroup: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            compactButton(
                systemName: "minus",
                accessibilityLabel: "Zoom out",
                action: perform(configuration.onZoomOut)
            )

            Text(configuration.zoomLabel)
                .appFont(.labelMd)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(minWidth: 56)

            compactButton(
                systemName: "plus",
                accessibilityLabel: "Zoom in",
                action: perform(configuration.onZoomIn)
            )
        }
    }

    private var fitGroup: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            fitIconButton(
                systemName: "distribute.horizontal",
                accessibilityLabel: "Fit to width",
                mode: .width
            )
            fitIconButton(
                systemName: "distribute.vertical",
                accessibilityLabel: "Fit to height",
                mode: .height
            )
        }
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: HeaderActionControlMetrics.iconFrameHeight)
            .accessibilityHidden(true)
    }

    private func compactButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .appFont(.labelMd)
            .foregroundStyle(.primary)
            .frame(
                width: HeaderActionControlMetrics.iconFrameWidth,
                height: HeaderActionControlMetrics.iconFrameHeight
            )
            .padding(HeaderActionControlMetrics.chromePadding)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func fitIconButton(
        systemName: String,
        accessibilityLabel: String,
        mode: PDFViewerController.FitMode
    ) -> some View {
        Button {
            configuration.onSetFitMode(mode)
            onDismissRequested()
        } label: {
            Image(systemName: systemName)
                .appFont(.labelMd)
                .foregroundStyle(configuration.fitMode == mode ? .primary : .secondary)
                .frame(
                    width: HeaderActionControlMetrics.iconFrameWidth,
                    height: HeaderActionControlMetrics.iconFrameHeight
                )
                .padding(HeaderActionControlMetrics.chromePadding)
                .background {
                    if configuration.fitMode == mode {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
