import SwiftUI

public struct SidebarRail: View {
    @Binding private var selection: AppSection?
    @State private var hoveredSection: AppSection?

    private let sections: [AppSection] = [
        .chat,
        .notes,
        .files,
        .websites
    ]

    public init(selection: Binding<AppSection?>) {
        self._selection = selection
    }

    public var body: some View {
        VStack(spacing: 16) {
            Button(action: {}) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            VStack(spacing: 12) {
                ForEach(sections) { section in
                    sectionButton(for: section)
                }
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 56)
        .padding(.vertical, 12)
        .background(railBackground)
    }

    private func sectionButton(for section: AppSection) -> some View {
        let isActive = selection == section
        let isHovered = hoveredSection == section

        return Button {
            selection = section
        } label: {
            Image(systemName: iconName(for: section))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(buttonBackground(isActive: isActive, isHovered: isHovered))
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovering in
            hoveredSection = isHovering ? section : nil
        }
        #endif
    }

    private func iconName(for section: AppSection) -> String {
        switch section {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .notes:
            return "note.text"
        case .files:
            return "folder"
        case .websites:
            return "globe"
        default:
            return "square.grid.2x2"
        }
    }

    private func buttonBackground(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }

    private var railBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
