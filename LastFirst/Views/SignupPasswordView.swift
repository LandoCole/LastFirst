import SwiftUI

struct SignupPasswordView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    let email: String

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var validationError: String?
    @FocusState private var isFieldFocused: Bool

    private let primaryColor = Color(hex: 0x463F3A)
    private let bgColor = Color(hex: 0xF4F3EE)
    private let secondaryColor = Color(hex: 0x8A817C)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 48)

                    // Logo
                    HStack {
                        Spacer()
                        Image("LogoWordmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 180)
                        Spacer()
                    }

                    Spacer().frame(height: 16)

                    // Title
                    Text("Glad you could join us!")
                        .font(.hedvigLettersSerif(24))
                        .foregroundStyle(primaryColor)

                    // Errors
                    if let error = validationError ?? authViewModel.errorMessage {
                        Text(error)
                            .font(.rethinkSans(14))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 14) {
                        // Email (read-only)
                        Text(email)
                            .font(.rethinkSans(16))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.clear)
                            .foregroundStyle(secondaryColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(secondaryColor, lineWidth: 1)
                            )

                        // Password with toggle
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("", text: $password, prompt: Text("Password (min 6 characters)").foregroundStyle(secondaryColor))
                                } else {
                                    SecureField("", text: $password, prompt: Text("Password (min 6 characters)").foregroundStyle(secondaryColor))
                                }
                            }
                            .font(.rethinkSans(16))
                            .textContentType(.newPassword)
                            .focused($isFieldFocused)

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(secondaryColor)
                            }
                        }
                        .padding()
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(secondaryColor, lineWidth: 1)
                        )

                        // Confirm password with toggle
                        HStack {
                            Group {
                                if showConfirmPassword {
                                    TextField("", text: $confirmPassword, prompt: Text("Confirm password").foregroundStyle(secondaryColor))
                                } else {
                                    SecureField("", text: $confirmPassword, prompt: Text("Confirm password").foregroundStyle(secondaryColor))
                                }
                            }
                            .font(.rethinkSans(16))
                            .textContentType(.newPassword)
                            .focused($isFieldFocused)

                            Button {
                                showConfirmPassword.toggle()
                            } label: {
                                Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(secondaryColor)
                            }
                        }
                        .padding()
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(secondaryColor, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal)
            }

            // Bottom pinned section
            VStack(spacing: 12) {
                // Create Account button
                Button {
                    Task { await handleSignup() }
                } label: {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create Account")
                                .font(.rethinkSans(16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(password.isEmpty || confirmPassword.isEmpty || authViewModel.isLoading)

                // Back
                if !isFieldFocused {
                    Button {
                        authViewModel.clearMessages()
                        authViewModel.authFlowPath.removeLast()
                    } label: {
                        Text("\u{2190} Back")
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
        .onAppear { authViewModel.clearMessages() }
    }

    private func handleSignup() async {
        validationError = nil

        guard password.count >= 6 else {
            validationError = "Password must be at least 6 characters"
            return
        }

        guard password == confirmPassword else {
            validationError = "Passwords do not match"
            return
        }

        await authViewModel.signUp(email: email, password: password)

        if authViewModel.errorMessage == nil {
            authViewModel.authFlowPath.append(.signupEmailConfirmation(email: email))
        }
    }
}
