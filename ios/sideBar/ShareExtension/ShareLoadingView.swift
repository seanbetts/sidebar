#if canImport(UIKit)
import UIKit

final class ShareLoadingView: ShareStateView {
    private let loadingImageView: UIImageView

    init(message: String) {
        let loadingImageView = UIImageView()
        loadingImageView.translatesAutoresizingMaskIntoConstraints = false
        loadingImageView.contentMode = .scaleAspectFit
        loadingImageView.clipsToBounds = true
        loadingImageView.image = ShareLoadingAsset.image(for: UITraitCollection.current)
        self.loadingImageView = loadingImageView
        super.init(message: message, accessoryView: loadingImageView, style: .minimal)
        NSLayoutConstraint.activate([
            loadingImageView.widthAnchor.constraint(equalToConstant: 44),
            loadingImageView.heightAnchor.constraint(equalToConstant: 44)
        ])
        observeUserInterfaceStyleChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func observeUserInterfaceStyleChanges() {
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.refreshLoadingImage()
        }
    }

    private func refreshLoadingImage() {
        loadingImageView.image = ShareLoadingAsset.image(for: traitCollection)
    }
}
#endif
