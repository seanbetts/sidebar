import SwiftUI

public struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false

    public init() {
    }

    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text("sideBar")
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
#if canImport(UIKit)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(fieldTextColor)
                    .background(fieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(fieldBorderColor, lineWidth: 1)
                    )

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(fieldTextColor)
                    .background(fieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(fieldBorderColor, lineWidth: 1)
                    )

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        ProgressView()
                            .tint(signInLabelColor)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .foregroundStyle(signInLabelColor)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(signInTintColor)
                .disabled(isSigningIn || email.isEmpty || password.isEmpty)
            }
        }
        .frame(maxWidth: 420)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var fieldBorderColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var fieldTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var signInTintColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var signInLabelColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await environment.container.authSession.signIn(email: email, password: password)
            environment.refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
