#if os(macOS)
import AppKit
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitPDFControlBar: NSView {
    private final class MenuButton: NSButton {
        var onClick: (@MainActor @Sendable () -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            target = self
            action = #selector(handleClick)
            translatesAutoresizingMaskIntoConstraints = false
            isBordered = false
            bezelStyle = .regularSquare
            setButtonType(.momentaryPushIn)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func handleClick() {
            onClick?()
        }
    }

    private let barContainerView = NSGlassEffectView()
    private let barContentView = NSView()
    private let menuButton = MenuButton()
    private var currentConfiguration: PDFControlBarConfiguration
    private var showsVisibleChrome: Bool
    private weak var popoverView: AppKitPDFControlPopoverView?
    private weak var dismissBackdropButton: NSButton?
    private static let barHeight: CGFloat = PDFControlBarChrome.entryControlHeight
    private static let barWidth: CGFloat = PDFControlBarChrome.entryControlWidth
    private static let horizontalPadding: CGFloat = 0
    private static let popoverScreenPadding: CGFloat = 8

    override init(frame frameRect: NSRect) {
        self.currentConfiguration = .disabled
        self.showsVisibleChrome = true
        super.init(frame: frameRect)
        setUpViewHierarchy()
        apply(configuration: .disabled, showsVisibleChrome: true)
    }

    convenience init(
        configuration: PDFControlBarConfiguration,
        showsVisibleChrome: Bool = true
    ) {
        self.init(frame: .zero)
        apply(configuration: configuration, showsVisibleChrome: showsVisibleChrome)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        configuration: PDFControlBarConfiguration,
        showsVisibleChrome: Bool? = nil
    ) {
        currentConfiguration = configuration
        if let showsVisibleChrome {
            self.showsVisibleChrome = showsVisibleChrome
        }

        menuButton.isEnabled = configuration.isEnabled
        if self.showsVisibleChrome,
           let image = NSImage(
                systemSymbolName: "doc.viewfinder",
                accessibilityDescription: nil
           )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(
                    pointSize: PDFControlBarChrome.entrySymbolPointSize,
                    weight: .semibold
                )
            ) {
            menuButton.image = image
        } else {
            menuButton.image = nil
        }
        menuButton.contentTintColor = self.showsVisibleChrome
            ? (configuration.isEnabled ? .labelColor : .secondaryLabelColor)
            : .clear
        barContainerView.isHidden = !self.showsVisibleChrome
        popoverView?.apply(configuration: configuration)

        if !configuration.isEnabled {
            dismissPopover()
        } else if popoverView?.isHidden == false {
            updatePopoverLayout()
        }
    }

    override func layout() {
        super.layout()
        if popoverView?.isHidden == false {
            updatePopoverLayout()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            dismissPopover()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyGlassChrome()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
struct AppKitPDFControlBarRepresentable: NSViewRepresentable {
    let configuration: PDFControlBarConfiguration
    let showsVisibleChrome: Bool

    init(
        configuration: PDFControlBarConfiguration,
        showsVisibleChrome: Bool = true
    ) {
        self.configuration = configuration
        self.showsVisibleChrome = showsVisibleChrome
    }

    func makeNSView(context: Context) -> AppKitPDFControlBar {
        AppKitPDFControlBar(
            configuration: configuration,
            showsVisibleChrome: showsVisibleChrome
        )
    }

    func updateNSView(_ nsView: AppKitPDFControlBar, context: Context) {
        nsView.apply(
            configuration: configuration,
            showsVisibleChrome: showsVisibleChrome
        )
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
struct AppKitPDFControlOverlay: View {
    let configuration: PDFControlBarConfiguration
    let showsVisibleChrome: Bool

    init(
        configuration: PDFControlBarConfiguration,
        showsVisibleChrome: Bool = true
    ) {
        self.configuration = configuration
        self.showsVisibleChrome = showsVisibleChrome
    }

    var body: some View {
        GeometryReader { proxy in
            AppKitPDFControlBarRepresentable(
                configuration: configuration,
                showsVisibleChrome: showsVisibleChrome
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitPDFControlPopoverView: NSView {
    private let backgroundEffectView = NSGlassEffectView()
    private let contentContainerView = NSView()
    private let hostingView: NSHostingView<PDFControlPopoverContent>
    private let onDismissRequested: @MainActor @Sendable () -> Void
    private var currentConfiguration: PDFControlBarConfiguration
    private var widthConstraint: NSLayoutConstraint?
    static let preferredPopoverWidth: CGFloat = 460

    init(
        configuration: PDFControlBarConfiguration,
        onDismissRequested: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.currentConfiguration = configuration
        self.onDismissRequested = onDismissRequested
        self.hostingView = NSHostingView(
            rootView: PDFControlPopoverContent(
                configuration: configuration,
                onDismissRequested: onDismissRequested
            )
        )
        super.init(frame: .zero)
        setUpViewHierarchy()
        apply(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: PDFControlBarConfiguration) {
        currentConfiguration = configuration
        hostingView.rootView = PDFControlPopoverContent(
            configuration: configuration,
            onDismissRequested: onDismissRequested
        )
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let resolvedWidth = min(maxWidth, Self.preferredPopoverWidth)
        let contentWidth = max(0, resolvedWidth - (DesignTokens.Spacing.sm * 2))
        widthConstraint?.constant = contentWidth
        frame.size = CGSize(width: resolvedWidth, height: 80)
        layoutSubtreeIfNeeded()
        let fitted = hostingView.fittingSize
        return CGSize(width: resolvedWidth, height: max(fitted.height, 52))
    }

    private func setUpViewHierarchy() {
        identifier = NSUserInterfaceItemIdentifier("pdf-control-popover")
        wantsLayer = true

        backgroundEffectView.identifier = NSUserInterfaceItemIdentifier("pdf-control-popover-glass")
        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.style = .regular
        backgroundEffectView.cornerRadius = 26
        backgroundEffectView.contentView = contentContainerView
        addSubview(backgroundEffectView)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(hostingView)

        let widthConstraint = hostingView.widthAnchor.constraint(equalToConstant: Self.preferredPopoverWidth)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: DesignTokens.Spacing.sm),
            hostingView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            hostingView.topAnchor.constraint(equalTo: contentContainerView.topAnchor, constant: DesignTokens.Spacing.xs),
            hostingView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor, constant: -DesignTokens.Spacing.xs),
            widthConstraint
        ])
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private extension AppKitPDFControlBar {
    func setUpViewHierarchy() {
        identifier = NSUserInterfaceItemIdentifier("pdf-control-bar-host")

        barContainerView.identifier = NSUserInterfaceItemIdentifier("pdf-control-bar")
        barContainerView.translatesAutoresizingMaskIntoConstraints = false
        barContainerView.style = .regular
        barContainerView.cornerRadius = PDFControlBarChrome.cornerRadius(for: Self.barHeight)
        barContainerView.wantsLayer = true
        applyGlassChrome()
        addSubview(barContainerView)

        barContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barContentView)

        menuButton.identifier = NSUserInterfaceItemIdentifier("pdf-control-menu")
        menuButton.setAccessibilityLabel("PDF controls")
        menuButton.imagePosition = .imageOnly
        menuButton.onClick = { [weak self] in
            self?.handleMenuButtonTap()
        }
        barContentView.addSubview(menuButton)

        NSLayoutConstraint.activate([
            barContainerView.topAnchor.constraint(equalTo: topAnchor),
            barContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            barContainerView.widthAnchor.constraint(equalToConstant: Self.barWidth),
            barContainerView.heightAnchor.constraint(equalToConstant: Self.barHeight),

            barContentView.topAnchor.constraint(equalTo: topAnchor),
            barContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            barContentView.widthAnchor.constraint(equalToConstant: Self.barWidth),
            barContentView.heightAnchor.constraint(equalToConstant: Self.barHeight),

            menuButton.leadingAnchor.constraint(equalTo: barContentView.leadingAnchor, constant: Self.horizontalPadding),
            menuButton.trailingAnchor.constraint(equalTo: barContentView.trailingAnchor, constant: -Self.horizontalPadding),
            menuButton.topAnchor.constraint(equalTo: barContentView.topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: barContentView.bottomAnchor)
        ])
    }

    func applyGlassChrome() {
        guard let layer = barContainerView.layer else { return }
        layer.cornerRadius = barContainerView.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = HeaderActionControlChromeBridge.borderColor(
            for: PDFControlBarChrome.entryControlChromeStyle,
            appearance: effectiveAppearance
        ).cgColor
        layer.masksToBounds = true
    }

    func handleMenuButtonTap() {
        if popoverView?.isHidden == false {
            dismissPopover()
        } else {
            presentPopover()
        }
    }

    func presentPopover() {
        let popover = ensurePopoverView()
        let backdrop = ensureDismissBackdropButton()
        popover.apply(configuration: currentConfiguration)
        backdrop.isHidden = false
        popover.isHidden = false
        updatePopoverLayout()
    }

    func dismissPopover() {
        popoverView?.isHidden = true
        dismissBackdropButton?.isHidden = true
    }

    @discardableResult
    func ensurePopoverView() -> AppKitPDFControlPopoverView {
        if let popoverView {
            if popoverView.superview !== self {
                popoverView.removeFromSuperview()
                addSubview(popoverView, positioned: .above, relativeTo: barContentView)
            }
            return popoverView
        }

        let popover = AppKitPDFControlPopoverView(configuration: currentConfiguration) { [weak self] in
            self?.dismissPopover()
        }
        popover.translatesAutoresizingMaskIntoConstraints = true
        popover.autoresizingMask = []
        popover.isHidden = true
        addSubview(popover, positioned: .above, relativeTo: barContentView)
        self.popoverView = popover
        return popover
    }

    @discardableResult
    func ensureDismissBackdropButton() -> NSButton {
        if let dismissBackdropButton {
            if dismissBackdropButton.superview !== self {
                dismissBackdropButton.removeFromSuperview()
                addSubview(dismissBackdropButton, positioned: .below, relativeTo: barContainerView)
            }
            dismissBackdropButton.frame = bounds
            return dismissBackdropButton
        }

        let button = NSButton(title: "", target: self, action: #selector(handleBackdropTap))
        button.identifier = NSUserInterfaceItemIdentifier("pdf-control-dismiss-backdrop")
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = [.width, .height]
        button.frame = bounds
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.isHidden = true
        addSubview(button, positioned: .below, relativeTo: barContainerView)
        dismissBackdropButton = button
        return button
    }

    @objc
    func handleBackdropTap() {
        dismissPopover()
    }

    func updatePopoverLayout() {
        guard let popover = popoverView else { return }
        dismissBackdropButton?.frame = bounds

        let maxWidth = max(
            0,
            min(
                AppKitPDFControlPopoverView.preferredPopoverWidth,
                bounds.width - (Self.popoverScreenPadding * 2)
            )
        )
        guard maxWidth > 0 else { return }

        let popoverSize = popover.preferredSize(maxWidth: maxWidth)
        let anchorFrame = menuButton.convert(menuButton.bounds, to: self)
        let proposedX = anchorFrame.maxX - popoverSize.width
        let maxX = bounds.width - Self.popoverScreenPadding - popoverSize.width
        let resolvedX = min(
            max(proposedX, Self.popoverScreenPadding),
            max(Self.popoverScreenPadding, maxX)
        )
        let resolvedY = min(
            anchorFrame.minY,
            max(Self.popoverScreenPadding, bounds.height - Self.popoverScreenPadding - popoverSize.height)
        )

        popover.frame = CGRect(
            origin: CGPoint(x: resolvedX, y: resolvedY),
            size: popoverSize
        ).integral
    }
}
#endif
