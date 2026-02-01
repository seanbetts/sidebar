import SwiftUI

#if os(iOS)
import UIKit

private struct UIKitContextMenuView<Content: View>: UIViewRepresentable {
    let items: [SidebarMenuItem]
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(rootView: content, items: items)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let host = context.coordinator.hostingController
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        container.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let interaction = UIContextMenuInteraction(delegate: context.coordinator)
        container.addInteraction(interaction)
        context.coordinator.interaction = interaction

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.items = items
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        let hostingController: UIHostingController<Content>
        var items: [SidebarMenuItem]
        weak var interaction: UIContextMenuInteraction?

        init(rootView: Content, items: [SidebarMenuItem]) {
            self.hostingController = UIHostingController(rootView: rootView)
            self.items = items
            super.init()
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: self.items.map { item in
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
                })
            }
        }
    }
}
#endif

extension View {
    @ViewBuilder
    func platformContextMenu(items: [SidebarMenuItem]) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            UIKitContextMenuView(items: items, content: self)
        } else {
            self.contextMenu {
                sidebarMenuItemsView(items)
            }
        }
        #else
        self.contextMenu {
            sidebarMenuItemsView(items)
        }
        #endif
    }
}
