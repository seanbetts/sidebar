import SwiftUI

/// Shared provider logo treatment for onboarding screens.
struct OnboardingProviderLogoBadge: View {
    let provider: AIPrimaryProvider
    let logoSize: CGFloat
    let containerSize: CGFloat

    var body: some View {
        Image(provider.onboardingLogoAssetName)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .frame(width: containerSize, height: containerSize)
            .background(Color.white)
            .clipShape(Circle())
    }
}
