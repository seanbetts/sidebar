import UIKit

final class ShareSuccessView: ShareStateView {
    private enum Layout {
        static let iconSize: CGFloat = 44
    }

    init(message: String) {
        let checkmarkImageView = UIImageView()
        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .systemGreen
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.accessibilityIdentifier = "share-success-icon"
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.heightAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true
        checkmarkImageView.widthAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true

        super.init(message: message, accessoryView: checkmarkImageView, spacingAfterTitle: 20)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
