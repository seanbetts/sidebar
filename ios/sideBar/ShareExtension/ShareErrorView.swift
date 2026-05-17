#if canImport(UIKit)
import UIKit
import sideBarShared

final class ShareErrorView: ShareStateView {
    private enum Layout {
        static let iconSize: CGFloat = 44
    }

    init(message: String) {
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(appIcon: AppIcon.Action.clearFilled)
        iconImageView.tintColor = .systemRed
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.heightAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true
        iconImageView.widthAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true

        super.init(
            message: message,
            accessoryView: iconImageView,
            spacingAfterAccessory: 20,
            style: .minimal
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
