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
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.setImage(UIImage(systemName: systemImage, withConfiguration: config), for: .normal)
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
