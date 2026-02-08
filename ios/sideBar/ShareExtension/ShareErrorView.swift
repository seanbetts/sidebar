import UIKit

final class ShareErrorView: ShareStateView {
    init(message: String) {
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: "xmark.circle.fill")
        iconImageView.tintColor = .label
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        iconImageView.widthAnchor.constraint(equalToConstant: 36).isActive = true

        super.init(message: message, accessoryView: iconImageView, spacingAfterTitle: 72)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
