import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @FocusState private var isFieldFocused: Bool

    private let primaryColor = Color(hex: 0x463F3A)
    private let bgColor = Color(hex: 0xF4F3EE)
    private let secondaryColor = Color(hex: 0x8A817C)

    var body: some View {
        NavigationStack(path: $authViewModel.authFlowPath) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 48)

                        // Logo
                        Image("LogoWordmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 180)

                        Spacer().frame(height: 16)

                        // Title
                        Text("Log in or create an account")
                            .font(.hedvigLettersSerif(24))
                            .foregroundStyle(primaryColor)
                            .multilineTextAlignment(.center)

                        // Error
                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.rethinkSans(14))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Email field
                        TextField("", text: $email, prompt: Text("Email address").foregroundStyle(secondaryColor))
                            .font(.rethinkSans(16))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .focused($isFieldFocused)
                            .padding()
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(secondaryColor, lineWidth: 1)
                            )
                            .padding(.horizontal)

                        // Divider with "or"
                        HStack {
                            Rectangle().frame(height: 1).foregroundStyle(secondaryColor.opacity(0.4))
                            Text("or")
                                .font(.rethinkSans(14))
                                .foregroundStyle(secondaryColor)
                            Rectangle().frame(height: 1).foregroundStyle(secondaryColor.opacity(0.4))
                        }
                        .padding(.horizontal)

                        // OAuth buttons
                        VStack(spacing: 12) {
                            Button {
                                authViewModel.errorMessage = "Sign in with Apple is coming soon!"
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "apple.logo")
                                        .font(.body)
                                    Text("Sign in with Apple")
                                        .font(.rethinkSans(16, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .overlay(
                                    Capsule()
                                        .stroke(secondaryColor, lineWidth: 1)
                                )
                                .foregroundStyle(primaryColor)
                            }

                            Button {
                                authViewModel.errorMessage = "Sign in with Google is coming soon!"
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.body)
                                    Text("Sign in with Google")
                                        .font(.rethinkSans(16, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .overlay(
                                    Capsule()
                                        .stroke(secondaryColor, lineWidth: 1)
                                )
                                .foregroundStyle(primaryColor)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Bottom pinned section
                VStack(spacing: 12) {
                    // Continue button
                    Button {
                        Task { await handleContinue() }
                    } label: {
                        Group {
                            if authViewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Continue")
                                    .font(.rethinkSans(16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(email.isEmpty || authViewModel.isLoading)

                    // Skip
                    if !isFieldFocused {
                        Button {
                            authViewModel.skipAuth = true
                        } label: {
                            Text("Create account later \u{2192}")
                                .font(.rethinkSans(14))
                                .foregroundStyle(primaryColor)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .onTapGesture { hideKeyboard() }
            .background(bgColor)
            .navigationBarHidden(true)
            .navigationDestination(for: AuthFlowStep.self) { step in
                switch step {
                case .loginPassword(let email):
                    LoginPasswordView(email: email)
                case .signupPassword(let email):
                    SignupPasswordView(email: email)
                case .signupEmailConfirmation(let email):
                    SignupEmailConfirmationView(email: email)
                case .signupNickname(let email):
                    SignupNicknameView(email: email)
                case .signupInterests:
                    SignupInterestsView()
                case .emailEntry:
                    EmptyView()
                }
            }
        }
    }

    private func handleContinue() async {
        authViewModel.clearMessages()

        guard authViewModel.isValidEmail(email) else {
            authViewModel.errorMessage = "Please enter a valid email address."
            return
        }

        let exists = await authViewModel.checkEmailExists(email: email)
        if exists {
            authViewModel.authFlowPath.append(.loginPassword(email: email))
        } else {
            authViewModel.authFlowPath.append(.signupPassword(email: email))
        }
    }
}
