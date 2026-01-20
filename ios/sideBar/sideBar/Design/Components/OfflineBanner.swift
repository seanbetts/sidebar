import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline - showing cached data")
                .font(DesignTokens.Typography.subheadlineSemibold)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.warning)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.top, DesignTokens.Spacing.xs)
    }
}
