import Foundation

@MainActor
class SummarizationViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var result: SupabaseManager.SummarizationResult?

    func summarize(
        text: String,
        preset: SupabaseManager.SummarizationPreset,
        customInstructions: String? = nil,
        model: String
    ) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            result = try await SupabaseManager.shared.summarizeContent(
                text: text,
                preset: preset,
                customInstructions: customInstructions,
                model: model
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
