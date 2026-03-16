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

    private let backgroundEffectView = NSVisualEffectView()
    private let menuButton = MenuButton()
    private var currentConfiguration: NoteFormattingBarConfiguration
    private var popoverPresentation: NoteFormattingBarPresentation
    private weak var popoverView: AppKitNoteFormattingPopoverView?
    private weak var dismissBackdropButton: NSButton?
    private static let barHeight: CGFloat = 48
    private static let horizontalPadding: CGFloat = 8
    private static let popoverScreenPadding: CGFloat = 8

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

    override var intrinsicContentSize: CGSize {
        CGSize(width: 44 + (Self.horizontalPadding * 2), height: Self.barHeight)
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
private extension AppKitNoteFormattingBar {
    func setUpViewHierarchy() {
        identifier = NSUserInterfaceItemIdentifier("note-formatting-bar")
        wantsLayer = true

        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.material = .menu
        backgroundEffectView.state = .active
        backgroundEffectView.blendingMode = .withinWindow
        backgroundEffectView.wantsLayer = true
        backgroundEffectView.layer?.cornerRadius = 18
        backgroundEffectView.layer?.cornerCurve = .continuous
        backgroundEffectView.layer?.masksToBounds = true
        addSubview(backgroundEffectView)

        menuButton.identifier = NSUserInterfaceItemIdentifier("note-formatting-menu")
        menuButton.setAccessibilityLabel("Formatting")
        menuButton.imagePosition = .imageOnly
        menuButton.onClick = { [weak self] in
            self?.handleMenuButtonTap()
        }
        addSubview(menuButton)

        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            menuButton.topAnchor.constraint(equalTo: topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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
        popover.superview?.addSubview(backdrop, positioned: .below, relativeTo: popover)
    }

    func dismissPopover() {
        popoverView?.isHidden = true
        dismissBackdropButton?.isHidden = true
    }

    @discardableResult
    func ensurePopoverView() -> AppKitNoteFormattingPopoverView {
        let hostView = hostingView()
        if let popoverView {
            if popoverView.superview !== hostView {
                popoverView.removeFromSuperview()
                hostView.addSubview(popoverView)
            }
            return popoverView
        }

        let popover = AppKitNoteFormattingPopoverView(configuration: currentConfiguration) { [weak self] in
            self?.dismissPopover()
        }
        popover.translatesAutoresizingMaskIntoConstraints = true
        popover.autoresizingMask = []
        popover.isHidden = true
        hostView.addSubview(popover)
        self.popoverView = popover
        return popover
    }

    @discardableResult
    func ensureDismissBackdropButton() -> NSButton {
        let hostView = hostingView()
        if let dismissBackdropButton {
            if dismissBackdropButton.superview !== hostView {
                dismissBackdropButton.removeFromSuperview()
                hostView.addSubview(dismissBackdropButton)
            }
            dismissBackdropButton.frame = hostView.bounds
            return dismissBackdropButton
        }

        let button = NSButton(title: "", target: self, action: #selector(handleBackdropTap))
        button.identifier = NSUserInterfaceItemIdentifier("note-formatting-dismiss-backdrop")
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = [.width, .height]
        button.frame = hostView.bounds
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.isHidden = true
        hostView.addSubview(button)
        dismissBackdropButton = button
        return button
    }

    @objc func handleBackdropTap() {
        dismissPopover()
    }

    func updatePopoverLayout() {
        guard let popover = popoverView else { return }
        let hostView = hostingView()
        let buttonFrame = menuButton.convert(menuButton.bounds, to: hostView)
        let preferredSize = popover.preferredSize(
            maxWidth: max(hostView.bounds.width - (Self.popoverScreenPadding * 2), 240)
        )

        let originX = max(
            Self.popoverScreenPadding,
            min(
                buttonFrame.maxX - preferredSize.width,
                hostView.bounds.width - preferredSize.width - Self.popoverScreenPadding
            )
        )
        let originY = max(
            Self.popoverScreenPadding,
            min(
                buttonFrame.minY,
                hostView.bounds.height - preferredSize.height - Self.popoverScreenPadding
            )
        )

        popover.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: preferredSize)
        dismissBackdropButton?.frame = hostView.bounds
    }

    func hostingView() -> NSView {
        window?.contentView ?? superview ?? self
    }
}
#endif
