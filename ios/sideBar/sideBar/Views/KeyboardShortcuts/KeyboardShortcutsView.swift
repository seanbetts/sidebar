#if os(iOS)
import SwiftUI

struct KeyboardShortcutsView: View {
    private let registry = KeyboardShortcutRegistry.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(ShortcutContext.allCases) { context in
                    if let shortcuts = registry.groupedShortcuts()[context] {
                        Section(context.title) {
                            ForEach(shortcuts) { shortcut in
                                KeyboardShortcutRow(shortcut: shortcut)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct KeyboardShortcutRow: View {
    let shortcut: KeyboardShortcut

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(shortcut.symbol)
                .font(DesignTokens.Typography.monoLabel)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(minWidth: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.title)
                    .font(DesignTokens.Typography.subheadlineSemibold)
                Text(shortcut.description)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }
}
#endif
