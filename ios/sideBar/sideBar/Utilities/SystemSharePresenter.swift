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

    static func share(url: URL, anchorID: String? = nil) {
        share(items: [url], anchorID: anchorID)
    }

    static func share(text: String, anchorID: String? = nil) {
        share(items: [text], anchorID: anchorID)
    }

    private static func share(items: [Any], anchorID: String?) {
        #if os(iOS)
        guard let target = iOSPresentationTarget(anchorID: anchorID) else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = target.sourceView
            popover.sourceRect = target.sourceRect
            if !target.usesExplicitAnchor {
                popover.permittedArrowDirections = []
            }
        }
        target.presenter.present(controller, animated: true)
        #elseif os(macOS)
        guard let target = macOSPresentationTarget(anchorID: anchorID) else { return }
        let picker = NSSharingServicePicker(items: items)
        activePicker = picker
        picker.show(relativeTo: target.sourceRect, of: target.sourceView, preferredEdge: .minY)
        #endif
    }

    #if os(iOS)
    struct IOSPresentationTarget {
        let presenter: UIViewController
        let sourceView: UIView
        let sourceRect: CGRect
        let usesExplicitAnchor: Bool
    }

    static func iOSPresentationTarget(anchorID: String?) -> IOSPresentationTarget? {
        guard let presenter = topViewController() else { return nil }
        if let anchorID,
           let anchorView = SystemShareAnchorRegistry.view(for: anchorID),
           anchorView.window != nil {
            return IOSPresentationTarget(
                presenter: presenter,
                sourceView: anchorView,
                sourceRect: resolvedAnchorRect(in: anchorView.bounds),
                usesExplicitAnchor: true
            )
        }
        return IOSPresentationTarget(
            presenter: presenter,
            sourceView: presenter.view,
            sourceRect: centeredPresentationRect(in: presenter.view.bounds),
            usesExplicitAnchor: false
        )
    }

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
    #elseif os(macOS)
    struct MacOSPresentationTarget {
        let sourceView: NSView
        let sourceRect: NSRect
        let usesExplicitAnchor: Bool
    }

    static func macOSPresentationTarget(
        anchorID: String?,
        fallbackWindow: NSWindow? = nil
    ) -> MacOSPresentationTarget? {
        if let anchorID,
           let anchorView = SystemShareAnchorRegistry.view(for: anchorID),
           anchorView.window != nil {
            return MacOSPresentationTarget(
                sourceView: anchorView,
                sourceRect: resolvedAnchorRect(in: anchorView.bounds),
                usesExplicitAnchor: true
            )
        }
        let resolvedFallbackWindow = fallbackWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let anchorView = resolvedFallbackWindow?.contentView else { return nil }
        return MacOSPresentationTarget(
            sourceView: anchorView,
            sourceRect: centeredPresentationRect(in: anchorView.bounds),
            usesExplicitAnchor: false
        )
    }
    #endif

    static func centeredPresentationRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    }

    private static func resolvedAnchorRect(in bounds: CGRect) -> CGRect {
        let hasSize = bounds.width > 1 || bounds.height > 1
        return hasSize ? bounds : centeredPresentationRect(in: bounds)
    }
}
