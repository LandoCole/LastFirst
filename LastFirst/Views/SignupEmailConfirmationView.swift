import SwiftUI

struct SignupEmailConfirmationView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    let email: String

    private let primaryColor = Color(hex: 0x463F3A)
    private let bgColor = Color(hex: 0xF4F3EE)
    private let secondaryColor = Color(hex: 0x8A817C)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 48)

                    // Logo
                    Image("LogoWordmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 180)

                    // Title
                    Text("Check your email")
                        .font(.hedvigLettersSerif(24))
                        .foregroundStyle(primaryColor)

                    // Body
                    Text("We sent a confirmation link to **\(email)**. Open your email and tap the link to continue.")
                        .font(.rethinkSans(16))
                        .foregroundStyle(primaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Open Mail button
                    Button {
                        if let url = URL(string: "message://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Mail")
                            .font(.rethinkSans(16, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .overlay(
                                Capsule()
                                    .stroke(secondaryColor, lineWidth: 1)
                            )
                            .foregroundStyle(primaryColor)
                    }
                    .padding(.horizontal)
                }
            }

            // Bottom pinned section
            VStack(spacing: 12) {
                // Back
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
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(bgColor)
        .navigationBarHidden(true)
        .onChange(of: authViewModel.isAuthenticated) { _, isAuth in
            if isAuth {
                // User confirmed email via deep link — advance to nickname
                authViewModel.authFlowPath.append(.signupNickname(email: email))
            }
        }
    }
}
