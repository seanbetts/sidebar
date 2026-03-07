import UIKit

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingBar: UIView {
    struct Configuration {
        let isBoldActive: Bool
        let isItalicActive: Bool
        let isUnderlineActive: Bool
        let isEnabled: Bool
        let onBoldTap: @MainActor () -> Void
        let onItalicTap: @MainActor () -> Void
        let onUnderlineTap: @MainActor () -> Void

        static let disabled = Configuration(
            isBoldActive: false,
            isItalicActive: false,
            isUnderlineActive: false,
            isEnabled: false,
            onBoldTap: {},
            onItalicTap: {},
            onUnderlineTap: {}
        )

        func isActive(_ formatting: NoteFormatting) -> Bool {
            switch formatting {
            case .bold:
                return isBoldActive
            case .italic:
                return isItalicActive
            case .underline:
                return isUnderlineActive
            }
        }

        func tapHandler(for formatting: NoteFormatting) -> @MainActor () -> Void {
            switch formatting {
            case .bold:
                return onBoldTap
            case .italic:
                return onItalicTap
            case .underline:
                return onUnderlineTap
            }
        }
    }

    private let stackView = UIStackView()
    private let boldButton: UIButton
    private let italicButton: UIButton
    private let underlineButton: UIButton
    private var currentConfiguration: Configuration

    override init(frame: CGRect) {
        self.boldButton = Self.makeButton(for: .bold)
        self.italicButton = Self.makeButton(for: .italic)
        self.underlineButton = Self.makeButton(for: .underline)
        self.currentConfiguration = .disabled
        super.init(frame: frame)
        setUpViewHierarchy()
        apply(configuration: .disabled)
    }

    convenience init(configuration: Configuration) {
        self.init(frame: .zero)
        apply(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: Configuration) {
        currentConfiguration = configuration
        for formatting in Self.buttonOrder {
            let button = button(for: formatting)
            let isActive = configuration.isActive(formatting)
            button.isEnabled = configuration.isEnabled
            button.isSelected = isActive
            button.tintColor = isActive ? .tintColor : .label
            button.backgroundColor = isActive ? UIColor.tintColor.withAlphaComponent(0.14) : .clear
        }
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

@available(iOS 26.0, *)
private extension UIKitNoteFormattingBar {
    static let buttonOrder: [NoteFormatting] = [.bold, .italic, .underline]

    static func makeButton(for formatting: NoteFormatting) -> UIButton {
        let button = UIButton(type: .system)
        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        button.configuration = buttonConfiguration
        button.setImage(UIImage(systemName: systemImage(for: formatting)), for: .normal)
        button.accessibilityLabel = accessibilityLabel(for: formatting)
        button.accessibilityIdentifier = accessibilityIdentifier(for: formatting)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        return button
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
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.quaternaryLabel.cgColor

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
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
#endif
