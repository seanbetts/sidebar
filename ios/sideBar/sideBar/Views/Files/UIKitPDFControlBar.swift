import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, *)
final class UIKitPDFControlBar: UIView {
    private let backgroundEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    let menuButton: UIButton
    private var currentConfiguration: PDFControlBarConfiguration
    private var showsVisibleChrome: Bool
    private(set) var popoverView: UIKitPDFControlPopoverView?
    private var dismissBackdropView: PopoverDismissBackdropView?
    private static let barHeight: CGFloat = PDFControlBarChrome.entryControlHeight
    private static let minimumButtonTouchTarget: CGFloat = PDFControlBarChrome.entryControlWidth
    private static let horizontalPadding: CGFloat = 0
    private static let verticalPadding: CGFloat = 0
    private static let popoverScreenPadding: CGFloat = 8

    override init(frame: CGRect) {
        self.menuButton = Self.makeMenuButton()
        self.currentConfiguration = .disabled
        self.showsVisibleChrome = true
        super.init(frame: frame)
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
        menuButton.configuration = Self.buttonConfiguration(showsVisibleChrome: self.showsVisibleChrome)
        backgroundEffectView.isHidden = !self.showsVisibleChrome
        popoverView?.apply(configuration: configuration)
        if !configuration.isEnabled {
            dismissPopover()
        } else if popoverView?.isHidden == false {
            updatePopoverLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        let buttonSize = menuButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let totalWidth = max(buttonSize.width, Self.minimumButtonTouchTarget) + (Self.horizontalPadding * 2)
        return CGSize(width: ceil(totalWidth), height: Self.barHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if popoverView?.isHidden == false {
            updatePopoverLayout()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            tearDownPopoverHostViews()
        }
        super.willMove(toWindow: newWindow)
    }
}

@MainActor
@available(iOS 26.0, *)
struct UIKitPDFControlBarRepresentable: UIViewRepresentable {
    let configuration: PDFControlBarConfiguration
    let showsVisibleChrome: Bool

    init(
        configuration: PDFControlBarConfiguration,
        showsVisibleChrome: Bool = true
    ) {
        self.configuration = configuration
        self.showsVisibleChrome = showsVisibleChrome
    }

    func makeUIView(context: Context) -> UIKitPDFControlBar {
        UIKitPDFControlBar(
            configuration: configuration,
            showsVisibleChrome: showsVisibleChrome
        )
    }

    func updateUIView(_ uiView: UIKitPDFControlBar, context: Context) {
        uiView.apply(
            configuration: configuration,
            showsVisibleChrome: showsVisibleChrome
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIKitPDFControlBar,
        context: Context
    ) -> CGSize? {
        uiView.intrinsicContentSize
    }
}

@MainActor
@available(iOS 26.0, *)
final class UIKitPDFControlPopoverView: UIView {
    static let preferredPopoverWidth: CGFloat = 460

    private let backgroundEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let hostingController: UIHostingController<PDFControlPopoverContent>
    private let onDismissRequested: @MainActor @Sendable () -> Void
    private var currentConfiguration: PDFControlBarConfiguration

    init(
        configuration: PDFControlBarConfiguration,
        onDismissRequested: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.currentConfiguration = configuration
        self.onDismissRequested = onDismissRequested
        self.hostingController = UIHostingController(
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
        hostingController.rootView = PDFControlPopoverContent(
            configuration: configuration,
            onDismissRequested: onDismissRequested
        )
    }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let resolvedWidth = min(maxWidth, Self.preferredPopoverWidth)
        let fitted = hostingController.sizeThatFits(
            in: CGSize(width: resolvedWidth, height: UIView.layoutFittingCompressedSize.height)
        )
        return CGSize(width: resolvedWidth, height: max(fitted.height, 52))
    }

    private func setUpViewHierarchy() {
        accessibilityIdentifier = "pdf-control-popover"
        backgroundColor = .clear
        clipsToBounds = false

        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.accessibilityIdentifier = "pdf-control-popover-glass"
        backgroundEffectView.clipsToBounds = true
        backgroundEffectView.layer.cornerCurve = .continuous
        backgroundEffectView.layer.cornerRadius = 26
        addSubview(backgroundEffectView)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

@available(iOS 26.0, *)
extension UIKitPDFControlBar {
    struct PopoverLayout: Equatable {
        let frame: CGRect
    }

    static func makeMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = buttonConfiguration()
        button.accessibilityLabel = "PDF controls"
        button.accessibilityIdentifier = "pdf-control-menu"
        button.showsMenuAsPrimaryAction = false
        return button
    }

    static func buttonConfiguration(showsVisibleChrome: Bool = true) -> UIButton.Configuration {
        var configuration: UIButton.Configuration = .plain()
        if showsVisibleChrome {
            configuration.image = UIImage(
                systemName: AppIcon.PDF.fitPage.rawValue,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: PDFControlBarChrome.entrySymbolPointSize,
                    weight: .semibold
                )
            )
        } else {
            configuration.image = nil
        }
        configuration.contentInsets = .zero
        configuration.background = .clear()
        configuration.baseForegroundColor = showsVisibleChrome ? .label : .clear
        return configuration
    }

    static func glassBorderColor(for traitCollection: UITraitCollection) -> UIColor {
        HeaderActionControlChromeBridge.borderColor(
            for: PDFControlBarChrome.entryControlChromeStyle,
            traitCollection: traitCollection
        )
    }

    @objc func handleMenuButtonTap() {
        if popoverView?.isHidden == false {
            dismissPopover()
        } else {
            presentPopover()
        }
    }

    func presentPopover() {
        let popover = ensurePopoverView()
        let backdrop = ensureDismissBackdropView()
        popover.apply(configuration: currentConfiguration)
        updatePopoverLayout()
        backdrop.isHidden = false
        popover.isHidden = false
        popover.superview?.bringSubviewToFront(backdrop)
        popover.superview?.bringSubviewToFront(popover)
    }

    func dismissPopover() {
        popoverView?.isHidden = true
        dismissBackdropView?.isHidden = true
    }

    func tearDownPopoverHostViews() {
        dismissPopover()
        popoverView?.removeFromSuperview()
        dismissBackdropView?.removeFromSuperview()
        popoverView = nil
        dismissBackdropView = nil
    }

    @discardableResult
    func ensurePopoverView() -> UIKitPDFControlPopoverView {
        let hostView = window ?? self
        if let popoverView {
            if popoverView.superview !== hostView {
                popoverView.removeFromSuperview()
                hostView.addSubview(popoverView)
            }
            return popoverView
        }

        let popover = UIKitPDFControlPopoverView(configuration: currentConfiguration) { [weak self] in
            self?.dismissPopover()
        }
        popover.translatesAutoresizingMaskIntoConstraints = true
        popover.autoresizingMask = []
        popover.isHidden = true
        hostView.addSubview(popover)

        popoverView = popover
        return popover
    }

    @discardableResult
    private func ensureDismissBackdropView() -> PopoverDismissBackdropView {
        let hostView = window ?? self
        if let dismissBackdropView {
            if dismissBackdropView.superview !== hostView {
                dismissBackdropView.removeFromSuperview()
                hostView.addSubview(dismissBackdropView)
                dismissBackdropView.frame = hostView.bounds
            }
            return dismissBackdropView
        }

        let dismissBackdropView = PopoverDismissBackdropView()
        dismissBackdropView.translatesAutoresizingMaskIntoConstraints = true
        dismissBackdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dismissBackdropView.frame = hostView.bounds
        dismissBackdropView.isHidden = true
        dismissBackdropView.accessibilityIdentifier = "pdf-control-dismiss-backdrop"
        dismissBackdropView.addAction(UIAction { [weak self] _ in
            self?.dismissPopover()
        }, for: .touchUpInside)
        hostView.addSubview(dismissBackdropView)
        self.dismissBackdropView = dismissBackdropView
        return dismissBackdropView
    }

    func updatePopoverLayout() {
        guard let popover = popoverView, let hostView = popover.superview else { return }
        dismissBackdropView?.frame = hostView.bounds
        let maxWidth = max(
            0,
            min(
                UIKitPDFControlPopoverView.preferredPopoverWidth,
                hostView.bounds.width - hostView.safeAreaInsets.left - hostView.safeAreaInsets.right - 16
            )
        )
        guard maxWidth > 0 else { return }

        let popoverSize = popover.preferredSize(maxWidth: maxWidth)
        let anchorFrame = menuButton.convert(menuButton.bounds, to: hostView)
        let layout = Self.resolvePopoverLayout(
            anchorFrame: anchorFrame,
            containerBounds: hostView.bounds,
            safeAreaInsets: hostView.safeAreaInsets,
            popoverSize: popoverSize
        )
        popover.frame = layout.frame.integral
        dismissBackdropView?.excludedFrames = []
    }

    static func resolvePopoverLayout(
        anchorFrame: CGRect,
        containerBounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        popoverSize: CGSize
    ) -> PopoverLayout {
        let horizontalMinX = safeAreaInsets.left + popoverScreenPadding
        let horizontalMaxX = containerBounds.width - safeAreaInsets.right - popoverScreenPadding - popoverSize.width
        let proposedX = anchorFrame.maxX - popoverSize.width
        let resolvedX = min(max(proposedX, horizontalMinX), max(horizontalMinX, horizontalMaxX))

        let topLimit = safeAreaInsets.top + popoverScreenPadding
        let bottomLimit = containerBounds.height - safeAreaInsets.bottom - popoverScreenPadding - popoverSize.height
        let proposedY = anchorFrame.minY
        let resolvedY = min(max(proposedY, topLimit), max(topLimit, bottomLimit))

        return PopoverLayout(
            frame: CGRect(origin: CGPoint(x: resolvedX, y: resolvedY), size: popoverSize)
        )
    }

    func setUpViewHierarchy() {
        accessibilityIdentifier = "pdf-control-bar"
        backgroundColor = .clear
        clipsToBounds = false
        registerForAppearanceChanges()

        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.isUserInteractionEnabled = false
        backgroundEffectView.clipsToBounds = true
        backgroundEffectView.layer.cornerCurve = .continuous
        backgroundEffectView.layer.cornerRadius = PDFControlBarChrome.cornerRadius(for: Self.barHeight)
        applyGlassChrome()
        addSubview(backgroundEffectView)

        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)

        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            menuButton.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            menuButton.widthAnchor.constraint(equalToConstant: Self.minimumButtonTouchTarget)
        ])

        menuButton.addTarget(self, action: #selector(handleMenuButtonTap), for: .touchUpInside)
    }

    func applyGlassChrome() {
        backgroundEffectView.layer.borderWidth = 1
        backgroundEffectView.layer.borderColor = Self.glassBorderColor(for: traitCollection).cgColor
    }

    func registerForAppearanceChanges() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyGlassChrome()
        }
    }
}

@available(iOS 26.0, *)
private final class PopoverDismissBackdropView: UIControl {
    var excludedFrames: [CGRect] = []

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !excludedFrames.contains(where: { $0.contains(point) })
    }
}
#endif
