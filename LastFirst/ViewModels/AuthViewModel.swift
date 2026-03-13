import Foundation
import Supabase

enum AuthFlowStep: Hashable {
    case emailEntry
    case loginPassword(email: String)
    case signupPassword(email: String)
    case signupEmailConfirmation(email: String)
    case signupNickname(email: String)
    case signupInterests
}

@MainActor
class AuthViewModel: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isCheckingAuth = true
    @Published var currentUser: User?
    @Published var userProfile: Profile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var authFlowPath: [AuthFlowStep] = []
    @Published var skipAuth = false
    @Published var needsOnboarding = false

    private var authStateTask: Task<Void, Never>?
    private let startTime = ContinuousClock.now
    private static let minimumSplashDuration: ContinuousClock.Duration = .milliseconds(1500)

    init() {
        // Intentionally empty — call start() from .task {} in the view layer
        // to avoid blocking app launch with Keychain/network I/O.
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call once from a SwiftUI `.task` modifier so work runs off the init path.
    func start() {
        guard authStateTask == nil,
              let client = SupabaseManager.shared.client else {
            Task { await finishCheckingAuth() }
            return
        }

        authStateTask = Task.detached { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                await self?.handleAuthEvent(event, session: session)
            }
        }
    }

    // MARK: - Auth State Handling

    private func handleAuthEvent(_ event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession:
            if let user = session?.user {
                currentUser = user
                isAuthenticated = true
                Task { await fetchProfile() }
            } else {
                currentUser = nil
                isAuthenticated = false
            }
            Task { await finishCheckingAuth() }
        case .signedIn:
            currentUser = session?.user
            isAuthenticated = true
        case .signedOut:
            currentUser = nil
            userProfile = nil
            isAuthenticated = false
            skipAuth = false
            Task { await finishCheckingAuth() }
        case .userUpdated, .tokenRefreshed:
            currentUser = session?.user
        default:
            break
        }
    }

    private func finishCheckingAuth() async {
        let elapsed = ContinuousClock.now - startTime
        let remaining = Self.minimumSplashDuration - elapsed
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        isCheckingAuth = false
    }

    // MARK: - Email Validation

    func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Email Check

    func checkEmailExists(email: String) async -> Bool {
        guard let client = SupabaseManager.shared.client else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result: Bool = try await client.rpc("check_email_exists", params: ["email_input": email])
                .execute()
                .value
            return result
        } catch {
            errorMessage = "Unable to check email. Please try again."
            return false
        }
    }

    // MARK: - Auth Actions

    /// Signs up the user but does NOT auto-login (email confirmation required).
    func signUp(email: String, password: String) async {
        guard let client = SupabaseManager.shared.client else {
            errorMessage = "Supabase is not configured."
            return
        }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await client.auth.signUp(
                email: email,
                password: password
            )
            needsOnboarding = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        guard let client = SupabaseManager.shared.client else {
            errorMessage = "Supabase is not configured."
            return
        }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            currentUser = session.user
            isAuthenticated = true
            await fetchProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() async {
        guard let client = SupabaseManager.shared.client else { return }
        isLoading = true
        do {
            try await client.auth.signOut()
            currentUser = nil
            userProfile = nil
            isAuthenticated = false
            authFlowPath = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func resetPassword(email: String) async {
        guard let client = SupabaseManager.shared.client else {
            errorMessage = "Supabase is not configured."
            return
        }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await client.auth.resetPasswordForEmail(email)
            successMessage = "Password reset email sent. Check your inbox."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func updateEmail(newEmail: String) async {
        guard let client = SupabaseManager.shared.client else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await client.auth.update(user: UserAttributes(email: newEmail))
            successMessage = "Confirmation email sent to \(newEmail)."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func updatePassword(newPassword: String) async {
        guard let client = SupabaseManager.shared.client else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await client.auth.update(user: UserAttributes(password: newPassword))
            successMessage = "Password updated successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func updateDisplayName(_ name: String) async {
        guard let client = SupabaseManager.shared.client,
              let userId = currentUser?.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await client.from("profiles")
                .update(["display_name": name])
                .eq("id", value: userId.uuidString)
                .execute()
            userProfile?.displayName = name
            successMessage = "Display name updated."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveInterests(_ interests: [String]) async {
        guard let client = SupabaseManager.shared.client,
              let userId = currentUser?.id else { return }
        isLoading = true

        do {
            try await client.from("profiles")
                .update(["interests": interests])
                .eq("id", value: userId.uuidString)
                .execute()
            userProfile?.interests = interests
        } catch {
            print("[AuthViewModel] Failed to save interests: \(error)")
        }
        isLoading = false
    }

    func deleteAccount() async {
        // Client SDK cannot call admin.deleteUser().
        // For MVP: sign out and document follow-up for edge function.
        await signOut()
    }

    // MARK: - Navigation Helpers

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Profile

    func fetchProfile() async {
        guard let client = SupabaseManager.shared.client,
              let userId = currentUser?.id else { return }
        do {
            let profile: Profile = try await client.from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            userProfile = profile
        } catch {
            print("[AuthViewModel] Failed to fetch profile: \(error)")
        }
    }
}
