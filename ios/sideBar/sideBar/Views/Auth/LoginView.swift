import SwiftUI

public struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

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

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
#if canImport(UIKit)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
#endif
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        ZStack {
                            Text("Sign In")
                            HStack(spacing: 8) {
                                ProgressView()
                                    .opacity(isSigningIn ? 1 : 0)
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSigningIn || email.isEmpty || password.isEmpty)
                }
                .onSubmit(handleSubmit)
            }
            .groupBoxStyle(LoginGroupBoxStyle())
        }
        .frame(maxWidth: 420)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(DesignTokens.Colors.background)
        .onChange(of: email) { _, _ in
            errorMessage = nil
        }
        .onChange(of: password) { _, _ in
            errorMessage = nil
        }
        .onAppear {
            focusedField = .email
        }
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEmail != email {
                email = trimmedEmail
            }
            try await environment.container.authSession.signIn(email: trimmedEmail, password: password)
            environment.refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleSubmit() {
        switch focusedField {
        case .email:
            focusedField = .password
        case .password:
            Task { await signIn() }
        case .none:
            break
        }
    }
}

private struct LoginGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            configuration.label
            configuration.content
        }
        .cardStyle()
    }
}
