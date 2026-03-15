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
    private static let barHeight: CGFloat = 48
    private static let minimumButtonTouchTarget: CGFloat = 44
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 0

    override init(frame: CGRect) {
        self.menuButton = Self.makeMenuButton()
        self.currentConfiguration = .disabled
        super.init(frame: frame)
        setUpViewHierarchy()
        apply(configuration: .disabled)
    }

    convenience init(configuration: NoteFormattingBarConfiguration) {
        self.init(frame: .zero)
        apply(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: NoteFormattingBarConfiguration) {
        currentConfiguration = configuration
        menuButton.isEnabled = configuration.isEnabled
        menuButton.menu = Self.makeMenu(configuration: configuration)
        menuButton.configuration = Self.buttonConfiguration()
    }

    override var intrinsicContentSize: CGSize {
        let buttonSize = menuButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let totalWidth = max(buttonSize.width, Self.minimumButtonTouchTarget) + (Self.horizontalPadding * 2)
        return CGSize(width: ceil(totalWidth), height: Self.barHeight)
    }
}

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingAccessoryView: UIView {
    static let trailingPadding: CGFloat = 12
    private static let leadingPadding: CGFloat = 12
    private static let bottomPadding: CGFloat = 8

    private let formattingBar: UIKitNoteFormattingBar

    init(configuration: NoteFormattingBarConfiguration) {
        self.formattingBar = UIKitNoteFormattingBar(configuration: configuration)
        super.init(frame: .zero)
        setUpViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: NoteFormattingBarConfiguration) {
        formattingBar.apply(configuration: configuration)
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

    func makeUIView(context: Context) -> UIKitNoteFormattingBar {
        UIKitNoteFormattingBar(configuration: configuration)
    }

    func updateUIView(_ uiView: UIKitNoteFormattingBar, context: Context) {
        uiView.apply(configuration: configuration)
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
private extension UIKitNoteFormattingBar {
    static func makeMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = buttonConfiguration()
        button.accessibilityLabel = "Formatting"
        button.accessibilityIdentifier = "note-formatting-menu"
        button.showsMenuAsPrimaryAction = true
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

    static func makeMenu(configuration: NoteFormattingBarConfiguration) -> UIMenu {
        let textStyleMenu = UIMenu(
            title: "Text Style",
            children: NoteTextStyle.allCases.map { style in
                UIAction(
                    title: style.displayName,
                    attributes: configuration.canApplyTextStyle(style) ? [] : [.disabled],
                    state: configuration.activeTextStyle == style ? .on : .off
                ) { _ in
                    configuration.selectTextStyle(style)
                }
            }
        )

        let inlineMenu = UIMenu(
            title: "Inline",
            children: [
                inlineAction("Bold", formatting: .bold, configuration: configuration),
                inlineAction("Italic", formatting: .italic, configuration: configuration),
                inlineAction("Underline", formatting: .underline, configuration: configuration),
                inlineAction("Strikethrough", formatting: .strikethrough, configuration: configuration),
                inlineAction("Inline Code", formatting: .inlineCode, configuration: configuration)
            ]
        )

        return UIMenu(children: [textStyleMenu, inlineMenu])
    }

    static func inlineAction(
        _ title: String,
        formatting: NoteFormatting,
        configuration: NoteFormattingBarConfiguration
    ) -> UIAction {
        UIAction(
            title: title,
            state: configuration.isActive(formatting) ? .on : .off
        ) { _ in
            configuration.tapHandler(for: formatting)()
        }
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
    }
}

@available(iOS 26.0, *)
private extension UIKitNoteFormattingAccessoryView {
    func setUpViewHierarchy() {
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth]
        translatesAutoresizingMaskIntoConstraints = false

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
