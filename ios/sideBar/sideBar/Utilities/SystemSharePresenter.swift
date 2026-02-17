import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum SystemSharePresenter {
    #if os(macOS)
    private static var activePicker: NSSharingServicePicker?
    #endif

    static func share(url: URL) {
        #if os(iOS)
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
        #elseif os(macOS)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let anchorView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        activePicker = picker
        let anchorRect = NSRect(x: anchorView.bounds.midX, y: anchorView.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .minY)
        #endif
    }

    #if os(iOS)
    private static func topViewController() -> UIViewController? {
        guard let root = keyWindow()?.rootViewController else { return nil }
        return topViewController(from: root)
    }

    private static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func topViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigationController = viewController as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabBarController = viewController as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return topViewController(from: selected)
        }
        return viewController
    }
    #endif
}
