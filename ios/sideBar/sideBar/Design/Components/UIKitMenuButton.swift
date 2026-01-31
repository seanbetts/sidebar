import SwiftUI

#if os(iOS)
struct MenuActionItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let handler: () -> Void
}

struct UIKitMenuButton: UIViewRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    let items: [MenuActionItem]

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        button.configuration = config
        button.setImage(UIImage(systemName: systemImage), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = makeMenu()
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.menu = makeMenu()
        uiView.accessibilityLabel = accessibilityLabel
    }

    private func makeMenu() -> UIMenu {
        let actions = items.map { item in
            let image = item.systemImage.flatMap { UIImage(systemName: $0) }
            return UIAction(
                title: item.title,
                image: image,
                attributes: item.role == .destructive ? .destructive : []
            ) { _ in
                DispatchQueue.main.async {
                    item.handler()
                }
            }
        }
        return UIMenu(children: actions)
    }
}
#endif
