import SwiftUI

public struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false

    public init() {
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign In")
                .font(.title2.weight(.semibold))

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
#if canImport(UIKit)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()

            SecureField("Password", text: $password)
                .textContentType(.password)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(isSigningIn || email.isEmpty || password.isEmpty)

                Button(role: .cancel) {
                    email = ""
                    password = ""
                    errorMessage = nil
                } label: {
                    Text("Clear")
                }
                .disabled(isSigningIn)
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
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
