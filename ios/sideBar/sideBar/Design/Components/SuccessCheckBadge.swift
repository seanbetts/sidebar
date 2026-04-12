import SwiftUI

struct SuccessCheckBadge: View {
    let size: CGFloat
    let symbolSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Image(systemName: "checkmark")
                .appScaledFont(size: symbolSize, weight: .bold)
                .foregroundStyle(foregroundColor)
        }
        .frame(width: size, height: size)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
}
