#if os(macOS)
import AppKit
import SwiftUI
import sideBarShared

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteFormattingBar: NSView {
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
    private var currentConfiguration: NoteFormattingBarConfiguration
    private var popoverPresentation: NoteFormattingBarPresentation
    private var showsVisibleChrome: Bool
    private weak var popoverView: AppKitNoteFormattingPopoverView?
    private weak var dismissBackdropButton: NSButton?
    private static let barHeight: CGFloat = NoteFormattingBarChrome.entryControlHeight
    private static let barWidth: CGFloat = NoteFormattingBarChrome.entryControlWidth
    private static let horizontalPadding: CGFloat = 0
    private static let popoverScreenPadding: CGFloat = 8
    private static let topOverlapAllowance: CGFloat = 2

    override init(frame frameRect: NSRect) {
        self.currentConfiguration = .disabled
        self.popoverPresentation = .floatingTopTrailing
        self.showsVisibleChrome = true
        super.init(frame: frameRect)
        setUpViewHierarchy()
        apply(configuration: .disabled, presentation: .floatingTopTrailing, showsVisibleChrome: true)
    }

    convenience init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing,
        showsVisibleChrome: Bool = true
    ) {
        self.init(frame: .zero)
        apply(configuration: configuration, presentation: presentation, showsVisibleChrome: showsVisibleChrome)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation? = nil,
        showsVisibleChrome: Bool? = nil
    ) {
        currentConfiguration = configuration
        if let presentation {
            popoverPresentation = presentation
        }
        if let showsVisibleChrome {
            self.showsVisibleChrome = showsVisibleChrome
        }

        menuButton.isEnabled = configuration.isEnabled
        if self.showsVisibleChrome,
           let image = NSImage(appIcon: AppIcon.Notes.formatting)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(
                    pointSize: NoteFormattingBarChrome.entrySymbolPointSize,
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

        if !configuration.isEnabled || popoverPresentation == .hidden {
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
struct AppKitNoteFormattingBarRepresentable: NSViewRepresentable {
    let configuration: NoteFormattingBarConfiguration
    let presentation: NoteFormattingBarPresentation
    let showsVisibleChrome: Bool

    init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing,
        showsVisibleChrome: Bool = true
    ) {
        self.configuration = configuration
        self.presentation = presentation
        self.showsVisibleChrome = showsVisibleChrome
    }

    func makeNSView(context: Context) -> AppKitNoteFormattingBar {
        AppKitNoteFormattingBar(
            configuration: configuration,
            presentation: presentation,
            showsVisibleChrome: showsVisibleChrome
        )
    }

    func updateNSView(_ nsView: AppKitNoteFormattingBar, context: Context) {
        nsView.apply(
            configuration: configuration,
            presentation: presentation,
            showsVisibleChrome: showsVisibleChrome
        )
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
struct AppKitNoteFormattingOverlay: View {
    let configuration: NoteFormattingBarConfiguration
    let presentation: NoteFormattingBarPresentation
    let showsVisibleChrome: Bool

    init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing,
        showsVisibleChrome: Bool = true
    ) {
        self.configuration = configuration
        self.presentation = presentation
        self.showsVisibleChrome = showsVisibleChrome
    }

    var body: some View {
        GeometryReader { proxy in
            AppKitNoteFormattingBarRepresentable(
                configuration: configuration,
                presentation: presentation,
                showsVisibleChrome: showsVisibleChrome
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private extension AppKitNoteFormattingBar {
    func setUpViewHierarchy() {
        identifier = NSUserInterfaceItemIdentifier("note-formatting-bar-host")

        barContainerView.identifier = NSUserInterfaceItemIdentifier("note-formatting-bar")
        barContainerView.translatesAutoresizingMaskIntoConstraints = false
        barContainerView.style = .regular
        barContainerView.cornerRadius = NoteFormattingBarChrome.cornerRadius(for: Self.barHeight)
        barContainerView.wantsLayer = true
        applyGlassChrome()
        addSubview(barContainerView)

        barContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barContentView)

        menuButton.identifier = NSUserInterfaceItemIdentifier("note-formatting-menu")
        menuButton.setAccessibilityLabel("Formatting")
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
        layer.borderColor = glassBorderColor.cgColor
        layer.masksToBounds = true
    }

    var glassBorderColor: NSColor {
        HeaderActionControlChromeBridge.borderColor(
            for: NoteFormattingBarChrome.entryControlChromeStyle,
            appearance: effectiveAppearance
        )
    }

    func handleMenuButtonTap() {
        if popoverView?.isHidden == false {
            dismissPopover()
        } else {
            presentPopover()
        }
    }

    func presentPopover() {
        guard popoverPresentation != .hidden else { return }

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
    func ensurePopoverView() -> AppKitNoteFormattingPopoverView {
        if let popoverView {
            if popoverView.superview !== self {
                popoverView.removeFromSuperview()
                addSubview(popoverView, positioned: .above, relativeTo: barContentView)
            }
            return popoverView
        }

        let popover = AppKitNoteFormattingPopoverView(configuration: currentConfiguration) { [weak self] in
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
        button.identifier = NSUserInterfaceItemIdentifier("note-formatting-dismiss-backdrop")
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

    @objc func handleBackdropTap() {
        dismissPopover()
    }

    func updatePopoverLayout() {
        guard let popover = popoverView else { return }
        let buttonFrame = menuButton.convert(menuButton.bounds, to: self)
        let preferredSize = popover.preferredSize(
            maxWidth: max(bounds.width - (Self.popoverScreenPadding * 2), 240)
        )

        let originX = max(
            Self.popoverScreenPadding,
            min(
                buttonFrame.maxX - preferredSize.width,
                bounds.width - preferredSize.width
            )
        )
        let anchoredOriginY = buttonFrame.maxY - preferredSize.height
        let originY = max(
            Self.popoverScreenPadding,
            min(
                anchoredOriginY,
                bounds.height - preferredSize.height + Self.topOverlapAllowance
            )
        )

        popover.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: preferredSize)
        dismissBackdropButton?.frame = bounds
    }
}
#endif
