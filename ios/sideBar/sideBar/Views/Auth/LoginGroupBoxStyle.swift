import SwiftUI

struct LoginGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            configuration.label
            configuration.content
        }
        .cardStyle()
    }
}
