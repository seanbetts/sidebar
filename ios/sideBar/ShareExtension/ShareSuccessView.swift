import UIKit

final class ShareSuccessView: UIView {
    private let checkmarkImageView = UIImageView()
    private let messageLabel = UILabel()

    init(message: String) {
        super.init(frame: .zero)
        setup(message: message)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(message: String) {
        backgroundColor = .systemBackground

        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .systemGreen
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmarkImageView)

        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .headline)
        messageLabel.textColor = .label
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            checkmarkImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 60),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 60),
            messageLabel.topAnchor.constraint(equalTo: checkmarkImageView.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])
    }
}
