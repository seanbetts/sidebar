#if canImport(UIKit)
import UIKit

final class ShareSuccessView: ShareStateView {
    private enum Layout {
        static let iconSize: CGFloat = 44
        static let checkmarkSize: CGFloat = 28
    }

    init(message: String) {
        let iconContainerView = UIView()
        iconContainerView.backgroundColor = Self.successCheckBackgroundColor
        iconContainerView.layer.cornerRadius = Layout.iconSize / 2
        iconContainerView.layer.cornerCurve = .continuous
        iconContainerView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.heightAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true
        iconContainerView.widthAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Layout.checkmarkSize, weight: .bold)
        let checkmarkImageView = UIImageView()
        checkmarkImageView.image = UIImage(systemName: "checkmark", withConfiguration: symbolConfig)
        checkmarkImageView.tintColor = Self.successCheckForegroundColor
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.accessibilityIdentifier = "share-success-icon"
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.addSubview(checkmarkImageView)
        NSLayoutConstraint.activate([
            checkmarkImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor)
        ])

        super.init(
            message: message,
            accessoryView: iconContainerView,
            spacingAfterTitle: 10,
            style: .minimal
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var successCheckForegroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        }
    }

    private static var successCheckBackgroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
    }
}
#endif
