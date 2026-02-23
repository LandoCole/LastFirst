import SwiftUI

struct AccountView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var editedDisplayName = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if authViewModel.isAuthenticated {
                    authenticatedContent
                } else {
                    AuthView()
                }
            }
            .navigationTitle(authViewModel.isAuthenticated ? "Account" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Authenticated Content

    private var authenticatedContent: some View {
        Form {
            // Messages
            if let error = authViewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            if let success = authViewModel.successMessage {
                Section {
                    Text(success)
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }

            // Profile
            Section("Profile") {
                HStack {
                    Text("Email")
                    Spacer()
                    Text(authViewModel.currentUser?.email ?? "—")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Display Name", text: $editedDisplayName)
                        .onSubmit {
                            Task { await authViewModel.updateDisplayName(editedDisplayName) }
                        }
                }
                .onAppear {
                    editedDisplayName = authViewModel.userProfile?.displayName ?? ""
                }
            }

            // Appearance
            Section("Appearance") {
                Picker("Appearance", selection: $appState.settings.appAppearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Reading Settings
            Section("Reading") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Default Speed")
                        Spacer()
                        Text("\(appState.settings.defaultWPM) WPM")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(appState.settings.defaultWPM) },
                            set: { appState.settings.defaultWPM = Int($0) }
                        ),
                        in: 50...1500,
                        step: 25
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Paragraph Breath")
                        Spacer()
                        Text("\(appState.settings.paragraphBreathMs)ms")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(appState.settings.paragraphBreathMs) },
                            set: { appState.settings.paragraphBreathMs = Int($0) }
                        ),
                        in: 0...1000,
                        step: 50
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Soft Start")
                        Spacer()
                        Text("\(Int(appState.settings.softStartPercentage * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $appState.settings.softStartPercentage,
                        in: 0.1...1.0,
                        step: 0.05
                    )
                }

                Picker("Default Mode", selection: $appState.settings.defaultReadingMode) {
                    ForEach(ReadingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            // Account Actions
            Section("Account") {
                if showChangeEmail {
                    VStack(spacing: 12) {
                        TextField("New Email", text: $newEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        Button("Update Email") {
                            Task {
                                await authViewModel.updateEmail(newEmail: newEmail)
                                showChangeEmail = false
                                newEmail = ""
                            }
                        }
                        .disabled(newEmail.isEmpty || authViewModel.isLoading)
                    }
                } else {
                    Button("Change Email") {
                        showChangeEmail = true
                    }
                }

                if showChangePassword {
                    VStack(spacing: 12) {
                        SecureField("New Password", text: $newPassword)
                            .textContentType(.newPassword)
                        SecureField("Confirm Password", text: $confirmPassword)
                        Button("Update Password") {
                            Task {
                                await authViewModel.updatePassword(newPassword: newPassword)
                                showChangePassword = false
                                newPassword = ""
                                confirmPassword = ""
                            }
                        }
                        .disabled(newPassword.isEmpty || newPassword != confirmPassword || authViewModel.isLoading)
                    }
                } else {
                    Button("Change Password") {
                        showChangePassword = true
                    }
                }
            }

            // Sign Out
            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await authViewModel.signOut() }
                }
                .disabled(authViewModel.isLoading)
            }

            // Danger Zone
            Section("Danger Zone") {
                Button("Delete Account", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .confirmationDialog(
                    "Delete Account",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete My Account", role: .destructive) {
                        Task { await authViewModel.deleteAccount() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone. All your data will be permanently removed.")
                }
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://lastfirst.app")!) {
                    HStack {
                        Text("Website")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            }
        }
    }
}
