import SwiftUI

struct SignupNicknameView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    let email: String

    @State private var nickname = ""
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
                    Text("What should we call you?")
                        .font(.hedvigLettersSerif(24))
                        .foregroundStyle(primaryColor)

                    // Nickname field
                    TextField("", text: $nickname, prompt: Text("Your nickname").foregroundStyle(secondaryColor))
                        .font(.rethinkSans(16))
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .focused($isFieldFocused)
                        .padding()
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(secondaryColor, lineWidth: 1)
                        )
                }
                .padding(.horizontal)
            }

            // Bottom pinned section
            VStack(spacing: 12) {
                // Continue button
                Button {
                    Task {
                        await authViewModel.updateDisplayName(nickname)
                        authViewModel.authFlowPath.append(.signupInterests)
                    }
                } label: {
                    Text("Continue")
                        .font(.rethinkSans(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(nickname.isEmpty)

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
    }
}
