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
        content
            .environment(\.sidebarIsHovered, resolvedIsHovered)
            .onHover { hovering in
                updateHoverState(hovering)
            }
            .onDisappear {
                updateCursor(active: false)
            }
    }

    private var resolvedIsHovered: Bool {
        externalIsHovered?.wrappedValue ?? isHovered
    }

    private func updateHoverState(_ hovering: Bool) {
        if externalIsHovered == nil {
            isHovered = hovering
        } else {
            externalIsHovered?.wrappedValue = hovering
        }

        updateCursor(active: hovering)
    }

    private func updateCursor(active: Bool) {
        #if os(macOS)
        guard let cursor else { return }

        if active {
            guard !isCursorActive else { return }
            cursor.nsCursor.push()
            isCursorActive = true
        } else if isCursorActive {
            NSCursor.pop()
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
}
