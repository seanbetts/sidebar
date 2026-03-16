#if os(macOS)
import AppKit
import SwiftUI

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
    private weak var popoverView: AppKitNoteFormattingPopoverView?
    private weak var dismissBackdropButton: NSButton?
    private static let barHeight: CGFloat = 52
    private static let barWidth: CGFloat = 60
    private static let horizontalPadding: CGFloat = 8
    private static let popoverScreenPadding: CGFloat = 8
    private static let topOverlapAllowance: CGFloat = 2

    override init(frame frameRect: NSRect) {
        self.currentConfiguration = .disabled
        self.popoverPresentation = .floatingTopTrailing
        super.init(frame: frameRect)
        setUpViewHierarchy()
        apply(configuration: .disabled, presentation: .floatingTopTrailing)
    }

    convenience init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing
    ) {
        self.init(frame: .zero)
        apply(configuration: configuration, presentation: presentation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation? = nil
    ) {
        currentConfiguration = configuration
        if let presentation {
            popoverPresentation = presentation
        }

        menuButton.isEnabled = configuration.isEnabled
        if let image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil) {
            menuButton.image = image
        }
        menuButton.contentTintColor = configuration.isEnabled ? .labelColor : .secondaryLabelColor
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

    init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing
    ) {
        self.configuration = configuration
        self.presentation = presentation
    }

    func makeNSView(context: Context) -> AppKitNoteFormattingBar {
        AppKitNoteFormattingBar(configuration: configuration, presentation: presentation)
    }

    func updateNSView(_ nsView: AppKitNoteFormattingBar, context: Context) {
        nsView.apply(configuration: configuration, presentation: presentation)
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
struct AppKitNoteFormattingOverlay: View {
    let configuration: NoteFormattingBarConfiguration
    let presentation: NoteFormattingBarPresentation

    init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing
    ) {
        self.configuration = configuration
        self.presentation = presentation
    }

    var body: some View {
        GeometryReader { proxy in
            AppKitNoteFormattingBarRepresentable(
                configuration: configuration,
                presentation: presentation
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
        barContainerView.cornerRadius = 18
        barContainerView.wantsLayer = true
        barContainerView.contentView = barContentView
        applyGlassChrome()
        addSubview(barContainerView)
        barContentView.translatesAutoresizingMaskIntoConstraints = false

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

            menuButton.leadingAnchor.constraint(equalTo: barContentView.leadingAnchor, constant: Self.horizontalPadding),
            menuButton.trailingAnchor.constraint(equalTo: barContentView.trailingAnchor, constant: -Self.horizontalPadding),
            menuButton.topAnchor.constraint(equalTo: barContentView.topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: barContentView.bottomAnchor)
        ])
    }

    func applyGlassChrome() {
        guard let layer = barContainerView.layer else { return }
        layer.borderWidth = 1
        layer.borderColor = glassBorderColor.cgColor
    }

    var glassBorderColor: NSColor {
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            NSColor.white.withAlphaComponent(0.22)
        default:
            NSColor.black.withAlphaComponent(0.12)
        }
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
                addSubview(popoverView, positioned: .above, relativeTo: barContainerView)
            }
            return popoverView
        }

        let popover = AppKitNoteFormattingPopoverView(configuration: currentConfiguration) { [weak self] in
            self?.dismissPopover()
        }
        popover.translatesAutoresizingMaskIntoConstraints = true
        popover.autoresizingMask = []
        popover.isHidden = true
        addSubview(popover, positioned: .above, relativeTo: barContainerView)
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
