import SwiftUI
#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingBar: UIView {
    private let backgroundEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let stackView = UIStackView()
    private let boldButton: UIButton
    private let italicButton: UIButton
    private let underlineButton: UIButton
    private var currentConfiguration: NoteFormattingBarConfiguration
    private static let barHeight: CGFloat = 44
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 6
    private static let buttonSpacing: CGFloat = 6

    override init(frame: CGRect) {
        self.boldButton = Self.makeButton(for: .bold)
        self.italicButton = Self.makeButton(for: .italic)
        self.underlineButton = Self.makeButton(for: .underline)
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
        for formatting in Self.buttonOrder {
            let button = button(for: formatting)
            let isActive = configuration.isActive(formatting)
            button.isEnabled = configuration.isEnabled
            button.isSelected = isActive
            button.configuration = Self.buttonConfiguration(for: formatting, isActive: isActive)
        }
    }

    override var intrinsicContentSize: CGSize {
        let buttonSizes = Self.buttonOrder.map {
            button(for: $0).systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        }
        let contentWidth = buttonSizes.reduce(0) { $0 + $1.width }
        let spacingWidth = CGFloat(max(Self.buttonOrder.count - 1, 0)) * Self.buttonSpacing
        let totalWidth = contentWidth + spacingWidth + (Self.horizontalPadding * 2)
        return CGSize(width: ceil(totalWidth), height: Self.barHeight)
    }

    func button(for formatting: NoteFormatting) -> UIButton {
        switch formatting {
        case .bold:
            return boldButton
        case .italic:
            return italicButton
        case .underline:
            return underlineButton
        }
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
    static let buttonOrder: [NoteFormatting] = [.bold, .italic, .underline]

    static func makeButton(for formatting: NoteFormatting) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = buttonConfiguration(for: formatting, isActive: false)
        button.accessibilityLabel = accessibilityLabel(for: formatting)
        button.accessibilityIdentifier = accessibilityIdentifier(for: formatting)
        return button
    }

    static func buttonConfiguration(
        for formatting: NoteFormatting,
        isActive: Bool
    ) -> UIButton.Configuration {
        var configuration: UIButton.Configuration = isActive ? .prominentGlass() : .clearGlass()
        configuration.buttonSize = UIButton.Configuration.Size.mini
        configuration.cornerStyle = UIButton.Configuration.CornerStyle.capsule
        configuration.image = UIImage(systemName: systemImage(for: formatting))
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7)
        configuration.baseForegroundColor = isActive ? UIColor.white : UIColor.label
        return configuration
    }

    static func systemImage(for formatting: NoteFormatting) -> String {
        switch formatting {
        case .bold:
            return "bold"
        case .italic:
            return "italic"
        case .underline:
            return "underline"
        }
    }

    static func accessibilityLabel(for formatting: NoteFormatting) -> String {
        switch formatting {
        case .bold:
            return "Bold"
        case .italic:
            return "Italic"
        case .underline:
            return "Underline"
        }
    }

    static func accessibilityIdentifier(for formatting: NoteFormatting) -> String {
        switch formatting {
        case .bold:
            return "note-formatting-bold"
        case .italic:
            return "note-formatting-italic"
        case .underline:
            return "note-formatting-underline"
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
        stackView.spacing = Self.buttonSpacing
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

        for formatting in Self.buttonOrder {
            let button = button(for: formatting)
            button.addAction(
                UIAction { [weak self] _ in
                    self?.currentConfiguration.tapHandler(for: formatting)()
                },
                for: .touchUpInside
            )
            stackView.addArrangedSubview(button)
        }
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
