import SwiftUI
#if os(macOS)
import AppKit
#endif

private struct SidebarHoverStateKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarIsHovered: Bool {
        get { self[SidebarHoverStateKey.self] }
        set { self[SidebarHoverStateKey.self] = newValue }
    }
}

enum SidebarHoverCursor {
    case pointingHand
    case resizeLeftRight

    #if os(macOS)
    var nsCursor: NSCursor {
        switch self {
        case .pointingHand:
            return .pointingHand
        case .resizeLeftRight:
            return .resizeLeftRight
        }
    }
    #endif
}

struct SidebarHoverModifier: ViewModifier {
    private let externalIsHovered: Binding<Bool>?
    private let cursor: SidebarHoverCursor?

    @State private var isHovered = false
    @State private var isCursorActive = false

    init(
        isHovered: Binding<Bool>? = nil,
        cursor: SidebarHoverCursor? = .pointingHand
    ) {
        self.externalIsHovered = isHovered
        self.cursor = cursor
    }

    func body(content: Content) -> some View {
        hoverTrackedContent(content)
            .environment(\.sidebarIsHovered, resolvedIsHovered)
            .refreshCursorAfterInteraction(
                isHovered: resolvedIsHovered,
                refresh: { updateCursor(active: true, refresh: true) }
            )
            .onDisappear {
                updateCursor(active: false)
            }
    }

    @ViewBuilder
    private func hoverTrackedContent(_ content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            content.onContinuousHover { phase in
                switch phase {
                case .active:
                    updateHoverState(true, refreshCursor: true)
                case .ended:
                    updateHoverState(false)
                }
            }
        } else {
            content.onHover { hovering in
                updateHoverState(hovering)
            }
        }
        #else
        content.onHover { hovering in
            updateHoverState(hovering)
        }
        #endif
    }

    private var resolvedIsHovered: Bool {
        externalIsHovered?.wrappedValue ?? isHovered
    }

    private func updateHoverState(_ hovering: Bool, refreshCursor: Bool = false) {
        if externalIsHovered == nil {
            isHovered = hovering
        } else {
            externalIsHovered?.wrappedValue = hovering
        }

        updateCursor(active: hovering, refresh: refreshCursor)
    }

    private func updateCursor(active: Bool, refresh: Bool = false) {
        #if os(macOS)
        guard let cursor else { return }

        if active {
            guard refresh || !isCursorActive else { return }
            cursor.nsCursor.set()
            isCursorActive = true
        } else if isCursorActive {
            NSCursor.arrow.set()
            isCursorActive = false
        }
        #endif
    }
}

extension View {
    func sidebarHover(cursor: SidebarHoverCursor? = .pointingHand) -> some View {
        modifier(SidebarHoverModifier(cursor: cursor))
    }

    func sidebarHover(
        _ isHovered: Binding<Bool>,
        cursor: SidebarHoverCursor? = .pointingHand
    ) -> some View {
        modifier(SidebarHoverModifier(isHovered: isHovered, cursor: cursor))
    }

    @ViewBuilder
    fileprivate func refreshCursorAfterInteraction(
        isHovered: Bool,
        refresh: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    guard isHovered else { return }
                    DispatchQueue.main.async {
                        refresh()
                    }
                }
        )
        #else
        self
        #endif
    }
}
