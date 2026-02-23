import SwiftUI

struct LoginPasswordView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    let email: String

    @State private var password = ""
    @State private var showPassword = false
    @State private var resetSent = false
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
                    Text("Glad to see you again!")
                        .font(.hedvigLettersSerif(24))
                        .foregroundStyle(primaryColor)

                    // Error
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.rethinkSans(14))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    // Success (reset sent)
                    if let success = authViewModel.successMessage {
                        Text(success)
                            .font(.rethinkSans(14))
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    if !resetSent {
                        VStack(spacing: 14) {
                            // Email (read-only input style)
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
                                        TextField("", text: $password, prompt: Text("Password").foregroundStyle(secondaryColor))
                                    } else {
                                        SecureField("", text: $password, prompt: Text("Password").foregroundStyle(secondaryColor))
                                    }
                                }
                                .font(.rethinkSans(16))
                                .textContentType(.password)
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

                            // Forgot password
                            HStack {
                                Spacer()
                                Button("Forgot Password?") {
                                    Task {
                                        await authViewModel.resetPassword(email: email)
                                        resetSent = true
                                    }
                                }
                                .font(.rethinkSans(14))
                                .foregroundStyle(primaryColor)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Bottom pinned section
            VStack(spacing: 12) {
                if !resetSent {
                    // Login button
                    Button {
                        Task {
                            await authViewModel.signIn(email: email, password: password)
                        }
                    } label: {
                        Group {
                            if authViewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Login")
                                    .font(.rethinkSans(16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(password.isEmpty || authViewModel.isLoading)
                }

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
}
