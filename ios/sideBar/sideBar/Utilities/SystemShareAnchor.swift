import SwiftUI

#if os(iOS)
import UIKit
typealias SystemShareAnchorPlatformView = UIView
#elseif os(macOS)
import AppKit
typealias SystemShareAnchorPlatformView = NSView
#endif

enum SystemShareAnchorID {
    static let websitesHeaderActionsMenu = "websites-header-actions-menu"
    static let websitesToolbarActionsMenu = "websites-toolbar-actions-menu"
    static let notesHeaderActionsMenu = "notes-header-actions-menu"
    static let notesToolbarActionsMenu = "notes-toolbar-actions-menu"

    static func websitesSidebarRow(_ websiteID: String) -> String {
        "websites-sidebar-row:\(websiteID)"
    }

    static func notesSidebarRow(_ noteID: String) -> String {
        "notes-sidebar-row:\(noteID)"
    }

    static func workspaceSurfaceActionsMenu(_ surfaceID: String) -> String {
        "workspace-surface-actions-menu:\(surfaceID)"
    }
}

@MainActor
enum SystemShareAnchorRegistry {
    private static var entries: [String: WeakAnchorBox] = [:]

    static func register(_ view: SystemShareAnchorPlatformView, for id: String) {
        entries[id] = WeakAnchorBox(view: view)
    }

    static func view(for id: String) -> SystemShareAnchorPlatformView? {
        guard let box = entries[id] else { return nil }
        guard let view = box.view else {
            entries.removeValue(forKey: id)
            return nil
        }
        return view
    }

    static func unregister(id: String, matching view: SystemShareAnchorPlatformView? = nil) {
        guard let box = entries[id] else { return }
        guard let registeredView = box.view else {
            entries.removeValue(forKey: id)
            return
        }
        guard view == nil || registeredView === view else { return }
        entries.removeValue(forKey: id)
    }

    static func resetForTesting() {
        entries.removeAll()
    }
}

private final class WeakAnchorBox {
    weak var view: SystemShareAnchorPlatformView?

    init(view: SystemShareAnchorPlatformView) {
        self.view = view
    }
}

private struct SystemShareAnchorModifier: ViewModifier {
    let id: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id {
            content.overlay {
                SystemShareAnchorCapture(anchorID: id)
                    .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func systemShareAnchor(id: String?) -> some View {
        modifier(SystemShareAnchorModifier(id: id))
    }
}

#if os(iOS)
private struct SystemShareAnchorCapture: UIViewRepresentable {
    let anchorID: String

    func makeUIView(context: Context) -> SystemShareAnchorCaptureView {
        let view = SystemShareAnchorCaptureView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.anchorID = anchorID
        return view
    }

    func updateUIView(_ uiView: SystemShareAnchorCaptureView, context: Context) {
        uiView.anchorID = anchorID
        uiView.registerCurrentAnchor()
    }
}

private final class SystemShareAnchorCaptureView: UIView {
    var anchorID: String? {
        didSet {
            if let oldValue, oldValue != anchorID {
                SystemShareAnchorRegistry.unregister(id: oldValue, matching: self)
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        registerCurrentAnchor()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        registerCurrentAnchor()
    }

    func registerCurrentAnchor() {
        guard let anchorID else { return }
        guard window != nil else {
            SystemShareAnchorRegistry.unregister(id: anchorID, matching: self)
            return
        }
        SystemShareAnchorRegistry.register(self, for: anchorID)
    }
}
#elseif os(macOS)
private struct SystemShareAnchorCapture: NSViewRepresentable {
    let anchorID: String

    func makeNSView(context: Context) -> SystemShareAnchorCaptureView {
        let view = SystemShareAnchorCaptureView()
        view.anchorID = anchorID
        return view
    }

    func updateNSView(_ nsView: SystemShareAnchorCaptureView, context: Context) {
        nsView.anchorID = anchorID
        nsView.registerCurrentAnchor()
    }
}

private final class SystemShareAnchorCaptureView: NSView {
    var anchorID: String? {
        didSet {
            if let oldValue, oldValue != anchorID {
                SystemShareAnchorRegistry.unregister(id: oldValue, matching: self)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerCurrentAnchor()
    }

    override func layout() {
        super.layout()
        registerCurrentAnchor()
    }

    func registerCurrentAnchor() {
        guard let anchorID else { return }
        guard window != nil else {
            SystemShareAnchorRegistry.unregister(id: anchorID, matching: self)
            return
        }
        SystemShareAnchorRegistry.register(self, for: anchorID)
    }
}
#endif
