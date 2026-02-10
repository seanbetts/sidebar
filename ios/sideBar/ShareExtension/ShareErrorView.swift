import UIKit

final class ShareErrorView: ShareStateView {
    init(
        message: String,
        retryAction: (() -> Void)?,
        openAppAction: (() -> Void)?,
        closeAction: @escaping () -> Void
    ) {
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: "xmark.circle.fill")
        iconImageView.tintColor = .label
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        iconImageView.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let actionsStack = UIStackView()
        actionsStack.axis = .vertical
        actionsStack.alignment = .fill
        actionsStack.spacing = 10
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.widthAnchor.constraint(equalToConstant: 220).isActive = true

        if let retryAction {
            let retryButton = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = "Try Again"
            retryButton.configuration = configuration
            retryButton.addAction(
                UIAction { _ in
                    retryAction()
                },
                for: .touchUpInside
            )
            actionsStack.addArrangedSubview(retryButton)
        }

        if let openAppAction {
            let openButton = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = "Open App"
            openButton.configuration = configuration
            openButton.addAction(
                UIAction { _ in
                    openAppAction()
                },
                for: .touchUpInside
            )
            actionsStack.addArrangedSubview(openButton)
        }

        let closeButton = UIButton(type: .system)
        var closeConfiguration = UIButton.Configuration.gray()
        closeConfiguration.title = "Close"
        closeButton.configuration = closeConfiguration
        closeButton.addAction(
            UIAction { _ in
                closeAction()
            },
            for: .touchUpInside
        )
        actionsStack.addArrangedSubview(closeButton)

        super.init(
            message: message,
            accessoryView: iconImageView,
            spacingAfterTitle: 72,
            footerView: actionsStack
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
