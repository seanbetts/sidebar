import SwiftUI
#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingBar: UIView {
    private let backgroundEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let stackView = UIStackView()
    let menuButton: UIButton
    private var currentConfiguration: NoteFormattingBarConfiguration
    private var popoverPresentation: NoteFormattingBarPresentation
    private(set) var popoverView: UIKitNoteFormattingPopoverView?
    private var dismissBackdropView: PopoverDismissBackdropView?
    private static let barHeight: CGFloat = 48
    private static let minimumButtonTouchTarget: CGFloat = 44
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 0
    private static let popoverSpacing: CGFloat = 10
    private static let popoverScreenPadding: CGFloat = 8

    override init(frame: CGRect) {
        self.menuButton = Self.makeMenuButton()
        self.currentConfiguration = .disabled
        self.popoverPresentation = .floatingTopTrailing
        super.init(frame: frame)
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
        menuButton.configuration = Self.buttonConfiguration()
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
            dismissPopover()
        }
        super.willMove(toWindow: newWindow)
    }
}

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingAccessoryView: UIView {
    static let trailingPadding: CGFloat = 12
    private static let leadingPadding: CGFloat = 12
    private static let bottomPadding: CGFloat = 8

    private let formattingBar: UIKitNoteFormattingBar

    init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .keyboardAccessory
    ) {
        self.formattingBar = UIKitNoteFormattingBar(
            configuration: configuration,
            presentation: presentation
        )
        super.init(frame: .zero)
        setUpViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation
    ) {
        formattingBar.apply(configuration: configuration, presentation: presentation)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: formattingBar.intrinsicContentSize.height + Self.bottomPadding
        )
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let fittedBarSize = formattingBar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let resolvedWidth: CGFloat

        if horizontalFittingPriority == .required,
           targetSize.width > 0,
           targetSize.width < UIView.layoutFittingExpandedSize.width {
            resolvedWidth = targetSize.width
        } else if bounds.width > 0 {
            resolvedWidth = bounds.width
        } else {
            resolvedWidth = fittedBarSize.width + Self.leadingPadding + Self.trailingPadding
        }

        return CGSize(width: resolvedWidth, height: fittedBarSize.height + Self.bottomPadding)
    }
}

@MainActor
@available(iOS 26.0, *)
struct UIKitNoteFormattingBarRepresentable: UIViewRepresentable {
    let configuration: NoteFormattingBarConfiguration
    let presentation: NoteFormattingBarPresentation

    init(
        configuration: NoteFormattingBarConfiguration,
        presentation: NoteFormattingBarPresentation = .floatingTopTrailing
    ) {
        self.configuration = configuration
        self.presentation = presentation
    }

    func makeUIView(context: Context) -> UIKitNoteFormattingBar {
        UIKitNoteFormattingBar(configuration: configuration, presentation: presentation)
    }

    func updateUIView(_ uiView: UIKitNoteFormattingBar, context: Context) {
        uiView.apply(configuration: configuration, presentation: presentation)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIKitNoteFormattingBar,
        context: Context
    ) -> CGSize? {
        uiView.intrinsicContentSize
    }
}

@available(iOS 26.0, *)
extension UIKitNoteFormattingBar {
    enum PopoverDirection: Equatable {
        case above
        case below
    }

    struct PopoverLayout: Equatable {
        let frame: CGRect
        let direction: PopoverDirection
    }

    static func makeMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = buttonConfiguration()
        button.accessibilityLabel = "Formatting"
        button.accessibilityIdentifier = "note-formatting-menu"
        button.showsMenuAsPrimaryAction = false
        return button
    }

    static func buttonConfiguration() -> UIButton.Configuration {
        var configuration: UIButton.Configuration = .plain()
        configuration.buttonSize = .mini
        configuration.image = UIImage(systemName: "textformat")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        configuration.background = .clear()
        configuration.baseForegroundColor = .label
        return configuration
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

    @discardableResult
    func ensurePopoverView() -> UIKitNoteFormattingPopoverView {
        let hostView = window ?? self
        if let popoverView {
            if popoverView.superview !== hostView {
                popoverView.removeFromSuperview()
                hostView.addSubview(popoverView)
            }
            return popoverView
        }

        let popover = UIKitNoteFormattingPopoverView(configuration: currentConfiguration) { [weak self] in
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
        dismissBackdropView.accessibilityIdentifier = "note-formatting-dismiss-backdrop"
        dismissBackdropView.addAction(UIAction { [weak self] _ in
            self?.dismissPopover()
        }, for: .touchUpInside)
        hostView.addSubview(dismissBackdropView)
        self.dismissBackdropView = dismissBackdropView
        return dismissBackdropView
    }

    func dismissPopoverIfNeeded(forTapLocation location: CGPoint, in hostView: UIView) {
        guard let popover = popoverView, popover.isHidden == false else { return }

        let anchorFrame = menuButton.convert(menuButton.bounds, to: hostView)
        let popoverFrame: CGRect
        if let popoverSuperview = popover.superview, popoverSuperview !== hostView {
            popoverFrame = popoverSuperview.convert(popover.frame, to: hostView)
        } else {
            popoverFrame = popover.frame
        }

        if popoverFrame.contains(location) || anchorFrame.contains(location) {
            return
        }

        dismissPopover()
    }

    func updatePopoverLayout() {
        guard let popover = popoverView, let hostView = popover.superview else { return }
        dismissBackdropView?.frame = hostView.bounds
        let maxWidth = max(
            0,
            min(380, hostView.bounds.width - hostView.safeAreaInsets.left - hostView.safeAreaInsets.right - 16)
        )
        guard maxWidth > 0 else { return }

        let popoverSize = popover.preferredSize(maxWidth: maxWidth)
        let anchorFrame = menuButton.convert(menuButton.bounds, to: hostView)
        let layout = Self.resolvePopoverLayout(
            anchorFrame: anchorFrame,
            containerBounds: hostView.bounds,
            safeAreaInsets: hostView.safeAreaInsets,
            popoverSize: popoverSize,
            presentation: popoverPresentation
        )
        popover.frame = layout.frame.integral
        let anchorExclusionFrame = menuButton.convert(menuButton.bounds.insetBy(dx: -8, dy: -8), to: hostView)
        dismissBackdropView?.excludedFrames = [anchorExclusionFrame]
    }

    static func resolvePopoverLayout(
        anchorFrame: CGRect,
        containerBounds: CGRect,
        safeAreaInsets: UIEdgeInsets,
        popoverSize: CGSize,
        presentation: NoteFormattingBarPresentation
    ) -> PopoverLayout {
        let horizontalMinX = safeAreaInsets.left + popoverScreenPadding
        let horizontalMaxX = containerBounds.width - safeAreaInsets.right - popoverScreenPadding - popoverSize.width
        let proposedX = anchorFrame.maxX - popoverSize.width
        let resolvedX = min(max(proposedX, horizontalMinX), max(horizontalMinX, horizontalMaxX))

        let topLimit = safeAreaInsets.top + popoverScreenPadding
        let bottomLimit = containerBounds.height - safeAreaInsets.bottom - popoverScreenPadding
        let availableAbove = anchorFrame.minY - topLimit - popoverSpacing
        let availableBelow = bottomLimit - anchorFrame.maxY - popoverSpacing
        let preferredDirection: PopoverDirection = presentation == .keyboardAccessory ? .above : .below

        let resolvedDirection = resolvePopoverDirection(
            preferredDirection: preferredDirection,
            availableAbove: availableAbove,
            availableBelow: availableBelow,
            popoverHeight: popoverSize.height
        )

        let resolvedY: CGFloat
        switch resolvedDirection {
        case .above:
            resolvedY = max(anchorFrame.minY - popoverSpacing - popoverSize.height, topLimit)
        case .below:
            resolvedY = min(anchorFrame.maxY + popoverSpacing, bottomLimit - popoverSize.height)
        }

        return PopoverLayout(
            frame: CGRect(origin: CGPoint(x: resolvedX, y: resolvedY), size: popoverSize),
            direction: resolvedDirection
        )
    }

    static func resolvePopoverDirection(
        preferredDirection: PopoverDirection,
        availableAbove: CGFloat,
        availableBelow: CGFloat,
        popoverHeight: CGFloat
    ) -> PopoverDirection {
        let fitsAbove = availableAbove >= popoverHeight
        let fitsBelow = availableBelow >= popoverHeight

        switch preferredDirection {
        case .above:
            if fitsAbove { return .above }
            if fitsBelow { return .below }
        case .below:
            if fitsBelow { return .below }
            if fitsAbove { return .above }
        }

        return availableBelow >= availableAbove ? .below : .above
    }

    func setUpViewHierarchy() {
        accessibilityIdentifier = "note-formatting-bar"
        backgroundColor = .clear
        clipsToBounds = false

        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.isUserInteractionEnabled = false
        backgroundEffectView.clipsToBounds = true
        backgroundEffectView.layer.cornerCurve = .continuous
        backgroundEffectView.layer.cornerRadius = Self.barHeight / 2
        addSubview(backgroundEffectView)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            heightAnchor.constraint(equalToConstant: Self.barHeight)
        ])

        stackView.addArrangedSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumButtonTouchTarget),
            menuButton.heightAnchor.constraint(equalToConstant: Self.minimumButtonTouchTarget)
        ])

        menuButton.addTarget(self, action: #selector(handleMenuButtonTap), for: .touchUpInside)
    }
}

@available(iOS 26.0, *)
private final class PopoverDismissBackdropView: UIControl {
    var excludedFrames: [CGRect] = []

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !excludedFrames.contains(where: { $0.contains(point) })
    }
}

@available(iOS 26.0, *)
private extension UIKitNoteFormattingAccessoryView {
    func setUpViewHierarchy() {
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth]
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false

        formattingBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formattingBar)

        NSLayoutConstraint.activate([
            formattingBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingPadding),
            formattingBar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.leadingPadding),
            formattingBar.topAnchor.constraint(equalTo: topAnchor),
            formattingBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomPadding)
        ])
    }
}
#endif
