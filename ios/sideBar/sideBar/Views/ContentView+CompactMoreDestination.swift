import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct CompactPhoneNavBarAppearanceConfigurator: UIViewControllerRepresentable {
    let backgroundColor: Color
    let isOpaque: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationController = uiViewController.navigationController else {
                return
            }
            let resolvedBackgroundColor = UIColor(backgroundColor)

            let appearance = UINavigationBarAppearance()
            if isOpaque {
                appearance.configureWithOpaqueBackground()
            } else {
                appearance.configureWithDefaultBackground()
            }
            appearance.backgroundEffect = nil
            appearance.backgroundColor = resolvedBackgroundColor
            appearance.shadowColor = .clear

            navigationController.navigationBar.isTranslucent = !isOpaque
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
            navigationController.navigationBar.compactAppearance = appearance
            navigationController.view.backgroundColor = resolvedBackgroundColor
            navigationController.visibleViewController?.view.backgroundColor = resolvedBackgroundColor
            uiViewController.parent?.view.backgroundColor = resolvedBackgroundColor
        }
    }
}
#endif

struct CompactPhoneMoreDestinationScaffold<Content: View>: View {
    let title: String
    let backgroundColor: Color
    let onBack: () -> Void
    let content: Content

    init(
        title: String,
        backgroundColor: Color,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        CompactPhoneRootSafeAreaView(backgroundColor: backgroundColor) {
            VStack(spacing: 0) {
                CompactPhoneMoreDestinationHeader(
                    title: title,
                    onBack: onBack
                )
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(backgroundColor)
        }
        .background(backgroundColor)
    }
}

private struct CompactPhoneMoreDestinationHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .appFont(.subheading)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .strokeBorder(DesignTokens.Colors.border.opacity(0.35))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .overlay {
            Text(title)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.sidebar)
    }
}
