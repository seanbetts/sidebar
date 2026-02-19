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
        context.coordinator.attachRecognizerIfNeeded(startingFrom: uiView.superview)
        DispatchQueue.main.async { [weak uiView] in
            context.coordinator.attachRecognizerIfNeeded(startingFrom: uiView?.superview)
        }
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detachRecognizer()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var hostView: UIView?
        weak var coordinateSpaceView: UIView?
        weak var leftSwipeRecognizer: UISwipeGestureRecognizer?
        weak var rightSwipeRecognizer: UISwipeGestureRecognizer?
        var onSwipeEnded: ((CGSize, CGFloat) -> Void)?
        var isEnabledProvider: (() -> Bool)?
        var regionWidthProvider: (() -> CGFloat)?
        var isLeftPanelExpandedProvider: (() -> Bool)?

        func attachRecognizerIfNeeded(startingFrom view: UIView?) {
            coordinateSpaceView = view
            guard let host = firstInteractiveAncestor(from: view) else { return }
            if hostView !== host {
                detachRecognizer()
                let leftRecognizer = UISwipeGestureRecognizer(
                    target: self,
                    action: #selector(handleSwipe(_:))
                )
                leftRecognizer.direction = .left
                leftRecognizer.numberOfTouchesRequired = 1
                leftRecognizer.cancelsTouchesInView = false
                leftRecognizer.delegate = self

                let rightRecognizer = UISwipeGestureRecognizer(
                    target: self,
                    action: #selector(handleSwipe(_:))
                )
                rightRecognizer.direction = .right
                rightRecognizer.numberOfTouchesRequired = 1
                rightRecognizer.cancelsTouchesInView = false
                rightRecognizer.delegate = self

                host.addGestureRecognizer(leftRecognizer)
                host.addGestureRecognizer(rightRecognizer)
                hostView = host
                leftSwipeRecognizer = leftRecognizer
                rightSwipeRecognizer = rightRecognizer
            }
            let isEnabled = isEnabledProvider?() ?? false
            leftSwipeRecognizer?.isEnabled = isEnabled
            rightSwipeRecognizer?.isEnabled = isEnabled
        }

        private func firstInteractiveAncestor(from view: UIView?) -> UIView? {
            var current = view
            while let candidate = current {
                if candidate.isUserInteractionEnabled {
                    return candidate
                }
                current = candidate.superview
            }
            return nil
        }

        func detachRecognizer() {
            if let leftSwipeRecognizer {
                leftSwipeRecognizer.view?.removeGestureRecognizer(leftSwipeRecognizer)
            }
            if let rightSwipeRecognizer {
                rightSwipeRecognizer.view?.removeGestureRecognizer(rightSwipeRecognizer)
            }
            leftSwipeRecognizer = nil
            rightSwipeRecognizer = nil
            hostView = nil
            coordinateSpaceView = nil
        }

        @objc func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
            guard isEnabledProvider?() == true else { return }
            guard let host = recognizer.view else { return }
            let coordinateView = coordinateSpaceView ?? host
            let location = recognizer.location(in: coordinateView)
            let translation: CGSize
            switch recognizer.direction {
            case .left:
                translation = CGSize(width: -WorkspaceSidebarSwipePolicy.minHorizontalDistance, height: 0)
            case .right:
                translation = CGSize(width: WorkspaceSidebarSwipePolicy.minHorizontalDistance, height: 0)
            default:
                return
            }
            let startX = location.x
            let regionWidth = regionWidthProvider?() ?? coordinateView.bounds.width
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
            isEnabledProvider?() ?? false
        }
    }
}
#endif
