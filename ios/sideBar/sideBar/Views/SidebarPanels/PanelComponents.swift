import SwiftUI

func panelHeaderBackground() -> Color {
    PlatformTokens.panelHeaderBackground
}

func sidebarSectionHeader(_ title: String) -> some View {
    Text(title)
        .appFont(.caption)
}
