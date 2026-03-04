#if os(iOS)
import UIKit

@available(iOS 26.0, *)
struct NoteInputAccessoryToolbarState {
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isBulletList = false
}

@available(iOS 26.0, *)
final class NoteInputAccessoryToolbarController: UIViewController {
    enum Action: CaseIterable {
        case bold
        case italic
        case underline
        case bulletList

        var symbolName: String {
            switch self {
            case .bold:
                return "bold"
            case .italic:
                return "italic"
            case .underline:
                return "underline"
            case .bulletList:
                return "list.bullet"
            }
        }

        var title: String {
            switch self {
            case .bold:
                return "Bold"
            case .italic:
                return "Italic"
            case .underline:
                return "Underline"
            case .bulletList:
                return "Bullets"
            }
        }

        var requiredCapability: NoteFormattingCapability {
            switch self {
            case .bold:
                return .bold
            case .italic:
                return .italic
            case .underline:
                return .underline
            case .bulletList:
                return .bulletList
            }
        }
    }

    var onAction: ((Action) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var buttons: [Action: UIButton] = [:]
    private var enabledCapabilities: Set<NoteFormattingCapability> = []
    private var state = NoteInputAccessoryToolbarState()

    override func loadView() {
        view = AccessoryContainerView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        rebuildButtons()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.94)
    }

    func setEnabledCapabilities(_ capabilities: Set<NoteFormattingCapability>) {
        guard enabledCapabilities != capabilities else { return }
        enabledCapabilities = capabilities
        rebuildButtons()
    }

    func setState(_ updatedState: NoteInputAccessoryToolbarState) {
        state = updatedState
        for action in Action.allCases {
            guard let button = buttons[action] else { continue }
            applyButtonStyle(button, isActive: isActive(action: action))
        }
    }

    private func configureLayout() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.backgroundColor = .clear

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func rebuildButtons() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons = [:]

        for action in Action.allCases where enabledCapabilities.contains(action.requiredCapability) {
            let button = makeButton(for: action)
            buttons[action] = button
            stackView.addArrangedSubview(button)
        }

        setState(state)
    }

    private func makeButton(for action: Action) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: action.symbolName), for: .normal)
        button.tintColor = .label
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor.tertiarySystemBackground.withAlphaComponent(0.8)
        button.accessibilityLabel = action.title
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        button.addAction(
            UIAction { [weak self] _ in
                self?.onAction?(action)
            },
            for: .touchUpInside
        )
        return button
    }

    private func isActive(action: Action) -> Bool {
        switch action {
        case .bold:
            return state.isBold
        case .italic:
            return state.isItalic
        case .underline:
            return state.isUnderline
        case .bulletList:
            return state.isBulletList
        }
    }

    private func applyButtonStyle(_ button: UIButton, isActive: Bool) {
        if isActive {
            button.tintColor = .systemBlue
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.16)
        } else {
            button.tintColor = .label
            button.backgroundColor = UIColor.tertiarySystemBackground.withAlphaComponent(0.8)
        }
    }
}

@available(iOS 26.0, *)
private final class AccessoryContainerView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }
}
#endif
