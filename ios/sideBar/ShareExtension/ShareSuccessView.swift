import UIKit

final class ShareSuccessView: ShareStateView {
    init(message: String) {
        let checkmarkImageView = UIImageView()
        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .label
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        checkmarkImageView.widthAnchor.constraint(equalToConstant: 36).isActive = true

        super.init(message: message, accessoryView: checkmarkImageView, spacingAfterTitle: 72)
    }
}
