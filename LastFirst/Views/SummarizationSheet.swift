import SwiftUI

struct SummarizationSheet: View {
    let text: String
    let title: String
    let sourceUrl: URL?
    let model: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @StateObject private var viewModel = SummarizationViewModel()
    @State private var customInstructions: String = ""
    @State private var selectedPreset: SupabaseManager.SummarizationPreset?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    loadingView
                } else if let result = viewModel.result {
                    completedView(result)
                } else {
                    presetPicker
                }
            }
            .padding(24)
            .navigationTitle("Summarize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Preset Picker

    private var presetPicker: some View {
        VStack(spacing: 16) {
            Text("How would you like this summarized?")
                .font(.hedvigLettersSerif(18))
                .multilineTextAlignment(.center)

            presetButton(
                icon: "bolt.fill",
                label: "Quick Summary",
                description: "2-3 paragraphs with key points",
                preset: .quick
            )

            presetButton(
                icon: "text.book.closed",
                label: "Simple Language",
                description: "Easy to read, all key info preserved",
                preset: .simple
            )

            VStack(spacing: 10) {
                presetButton(
                    icon: "pencil.line",
                    label: "Something Else",
                    description: "Your own instructions",
                    preset: .custom
                )

                if selectedPreset == .custom {
                    TextField("e.g., Focus on the methodology...", text: $customInstructions, axis: .vertical)
                        .font(.rethinkSans(14))
                        .lineLimit(3...6)
                        .padding(12)
                        .background(Color.warmBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        startSummarization(preset: .custom)
                    } label: {
                        Text("Summarize")
                            .font(.rethinkSans(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(customInstructions.isEmpty ? Color.gray : Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(customInstructions.isEmpty)
                }
            }

            Spacer()
        }
    }

    private func presetButton(icon: String, label: String, description: String, preset: SupabaseManager.SummarizationPreset) -> some View {
        Button {
            if preset == .custom {
                withAnimation { selectedPreset = .custom }
            } else {
                startSummarization(preset: preset)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.rethinkSans(16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.warmBackground)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Summarizing...")
                .font(.rethinkSans(15))
                .foregroundStyle(.secondary)

            if let error = viewModel.error {
                Text(error)
                    .font(.rethinkSans(13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }

    // MARK: - Completed

    private func completedView(_ result: SupabaseManager.SummarizationResult) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Summary ready")
                    .font(.rethinkSans(16, weight: .semibold))
            }

            Text("\(result.wordCount) words")
                .font(.rethinkSans(13))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(result.summary)
                    .font(.rethinkSans(14))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .background(Color.warmBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                readerCoordinator.openSummarizedContent(
                    text: result.summary,
                    title: title,
                    sourceUrl: sourceUrl,
                    appState: appState
                )
                dismiss()
            } label: {
                Text("Read Summary")
                    .font(.rethinkSans(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Actions

    private func startSummarization(preset: SupabaseManager.SummarizationPreset) {
        Task {
            await viewModel.summarize(
                text: text,
                preset: preset,
                customInstructions: preset == .custom ? customInstructions : nil,
                model: model
            )
        }
    }
}
