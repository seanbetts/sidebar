import SwiftUI

struct LoginPrimaryActionLabel: View {
    let isLoading: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                Text("Signing in...")
            }
            .opacity(0)

            if isLoading {
                HStack(spacing: 8) {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                    Text("Signing in...")
                }
            } else {
                Text("Sign in")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct LoginManualSignUpPrompt: View {
    let action: () -> Void

    var body: some View {
        Button("Don't have an account yet? Sign Up", action: action)
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }
}
