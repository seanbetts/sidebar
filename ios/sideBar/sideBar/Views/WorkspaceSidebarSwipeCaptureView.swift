import SwiftUI
#if os(iOS)
import UIKit

struct WorkspaceSidebarSwipeCaptureView: UIViewRepresentable {
    let isEnabled: Bool
    let regionWidth: CGFloat
    let isLeftPanelExpanded: Bool
    let onSwipeEnded: (CGSize, CGFloat) -> Void

    final class AnchorView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false

        context.coordinator.onSwipeEnded = onSwipeEnded
        context.coordinator.isEnabledProvider = { isEnabled }
        context.coordinator.regionWidthProvider = { regionWidth }
        context.coordinator.isLeftPanelExpandedProvider = { isLeftPanelExpanded }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.onSwipeEnded = onSwipeEnded
        context.coordinator.isEnabledProvider = { isEnabled }
        context.coordinator.regionWidthProvider = { regionWidth }
        context.coordinator.isLeftPanelExpandedProvider = { isLeftPanelExpanded }
        context.coordinator.attachRecognizerIfNeeded(anchorView: uiView)

        DispatchQueue.main.async { [weak uiView] in
            guard let uiView else { return }
            context.coordinator.attachRecognizerIfNeeded(anchorView: uiView)
        }
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detachRecognizer()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var anchorView: UIView?
        weak var hostWindow: UIWindow?
        weak var panRecognizer: UIPanGestureRecognizer?
        var gestureStartPoint: CGPoint?

        var onSwipeEnded: ((CGSize, CGFloat) -> Void)?
        var isEnabledProvider: (() -> Bool)?
        var regionWidthProvider: (() -> CGFloat)?
        var isLeftPanelExpandedProvider: (() -> Bool)?

        func attachRecognizerIfNeeded(anchorView: UIView) {
            self.anchorView = anchorView
            guard let window = anchorView.window else { return }

            if hostWindow !== window {
                detachRecognizer()

                let recognizer = UIPanGestureRecognizer(
                    target: self,
                    action: #selector(handlePan(_:))
                )
                recognizer.minimumNumberOfTouches = 1
                recognizer.maximumNumberOfTouches = 1
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
                recognizer.delegate = self

                window.addGestureRecognizer(recognizer)
                hostWindow = window
                panRecognizer = recognizer
            }

            panRecognizer?.isEnabled = isEnabledProvider?() ?? false
        }

        func detachRecognizer() {
            if let panRecognizer {
                panRecognizer.view?.removeGestureRecognizer(panRecognizer)
            }
            panRecognizer = nil
            hostWindow = nil
            anchorView = nil
            gestureStartPoint = nil
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard isEnabledProvider?() == true else { return }
            guard let anchorView,
                  let window = hostWindow ?? recognizer.view as? UIWindow else { return }

            let locationInWindow = recognizer.location(in: window)
            let locationInAnchor = anchorView.convert(locationInWindow, from: window)

            switch recognizer.state {
            case .began:
                gestureStartPoint = locationInAnchor
            case .ended, .cancelled, .failed:
                guard let start = gestureStartPoint else { return }
                defer { gestureStartPoint = nil }

                let end = locationInAnchor
                let translation = CGSize(width: end.x - start.x, height: end.y - start.y)
                let startX = start.x
                let regionWidth = regionWidthProvider?() ?? anchorView.bounds.width
                let isLeftPanelExpanded = isLeftPanelExpandedProvider?() ?? false

                let action = WorkspaceSidebarSwipePolicy.resolveAction(
                    translation: translation,
                    startX: startX,
                    regionWidth: regionWidth,
                    isLeftPanelExpanded: isLeftPanelExpanded,
                    isIPad: true
                )
                guard action != .none else { return }
                onSwipeEnded?(translation, startX)
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard isEnabledProvider?() == true else { return false }
            guard let anchorView else { return false }

            let locationInAnchor = touch.location(in: anchorView)
            let regionWidth = regionWidthProvider?() ?? anchorView.bounds.width
            return locationInAnchor.y >= 0 &&
                locationInAnchor.y <= anchorView.bounds.height &&
                locationInAnchor.x >= 0 &&
                locationInAnchor.x <= regionWidth
        }
    }
}
#endif
