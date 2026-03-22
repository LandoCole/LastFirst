import SwiftUI

struct CurationRequestForm: View {
    let onSubmit: (String) -> Void

    @State private var contentType: String?
    @State private var readingTime: String?
    @State private var selectedTopics: Set<String> = []
    @State private var selectedFormats: Set<String> = []
    @State private var cost: String?
    @State private var discovery: String?
    @State private var customPrompt: String = ""
    @FocusState private var isPromptFocused: Bool

    private let gold = Color(hex: "B08D57")

    private var canSubmit: Bool {
        contentType != nil || readingTime != nil || !selectedTopics.isEmpty
            || !selectedFormats.isEmpty || cost != nil || discovery != nil
            || !customPrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("What are you in the mood for?")
                        .font(.hedvigLettersSerif(22))
                    Text("Select your preferences and we'll curate something great.")
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                }

                // Content Type
                preferenceSection(
                    title: "Content type",
                    multiSelect: false,
                    options: [
                        ("fiction", "Fiction", "📖"),
                        ("nonfiction", "Non-fiction", "📊"),
                        ("either", "Either works", nil),
                    ],
                    selection: singleBinding($contentType)
                )

                // Reading Time
                preferenceSection(
                    title: "How much time do you have?",
                    multiSelect: false,
                    options: [
                        ("quick", "Quick read (<1 hr)", "⚡"),
                        ("medium", "Medium (1-5 hrs)", "⏱️"),
                        ("deep", "Deep dive (5+ hrs)", "📚"),
                    ],
                    selection: singleBinding($readingTime)
                )

                // Topics
                multiPreferenceSection(
                    title: "Topics or genres",
                    hint: "(select multiple)",
                    options: [
                        ("science_tech", "Science/Tech", "🔬"),
                        ("philosophy", "Philosophy/Ideas", "💡"),
                        ("history", "History", "🏛️"),
                        ("psychology", "Psychology", "🧠"),
                        ("business", "Business/Finance", "📈"),
                        ("self_help", "Self-improvement", "🌱"),
                        ("mystery", "Mystery/Thriller", "🔍"),
                        ("scifi", "Sci-Fi/Fantasy", "🚀"),
                        ("biography", "Biography/Memoir", "👤"),
                        ("politics", "Politics/Society", "🌍"),
                    ],
                    selection: $selectedTopics
                )

                // Format
                multiPreferenceSection(
                    title: "Format",
                    hint: "(select multiple)",
                    options: [
                        ("epub", "ePub", "📱"),
                        ("pdf", "PDF", "📄"),
                        ("web", "Articles/Websites", "🌐"),
                    ],
                    selection: $selectedFormats
                )

                // Cost
                preferenceSection(
                    title: "Cost",
                    multiSelect: false,
                    options: [
                        ("free", "Free only", nil),
                        ("paid", "Include paid", nil),
                        ("no_pref", "No preference", nil),
                    ],
                    selection: singleBinding($cost)
                )

                // Discovery
                preferenceSection(
                    title: "What kind of finds?",
                    multiSelect: false,
                    options: [
                        ("popular", "Popular/Bestsellers", "⭐"),
                        ("hidden", "Hidden gems", "💎"),
                        ("mix", "Mix of both", nil),
                    ],
                    selection: singleBinding($discovery)
                )

                // Custom prompt
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anything specific?")
                        .font(.rethinkSans(13, weight: .medium))

                    TextField("e.g. \"focused on AI ethics\" or \"beginner-friendly\"", text: $customPrompt, axis: .vertical)
                        .font(.rethinkSans(13))
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color.warmBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .focused($isPromptFocused)
                }

                // Submit button
                Button {
                    onSubmit(buildPrompt())
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Curate")
                            .font(.rethinkSans(16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? gold : Color.secondary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmit)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    // MARK: - Preference Section (single-select)

    private func preferenceSection(
        title: String,
        multiSelect: Bool,
        options: [(id: String, label: String, emoji: String?)],
        selection: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.rethinkSans(13, weight: .medium))

            FlowLayout(spacing: 8) {
                ForEach(options, id: \.id) { option in
                    let isSelected = selection.wrappedValue.contains(option.id)
                    chipButton(label: option.label, emoji: option.emoji, isSelected: isSelected) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selection.wrappedValue = [option.id]
                        }
                    }
                }
            }
        }
    }

    // MARK: - Multi-select Section

    private func multiPreferenceSection(
        title: String,
        hint: String,
        options: [(id: String, label: String, emoji: String?)],
        selection: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.rethinkSans(13, weight: .medium))
                Text(hint)
                    .font(.rethinkSans(11))
                    .foregroundStyle(.tertiary)
            }

            FlowLayout(spacing: 8) {
                ForEach(options, id: \.id) { option in
                    let isSelected = selection.wrappedValue.contains(option.id)
                    chipButton(label: option.label, emoji: option.emoji, isSelected: isSelected) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if isSelected {
                                selection.wrappedValue.remove(option.id)
                            } else {
                                selection.wrappedValue.insert(option.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chip Button

    private func chipButton(label: String, emoji: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 14))
                }
                Text(label)
                    .font(.rethinkSans(13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? gold.opacity(0.15) : Color.warmBackground)
            .foregroundStyle(isSelected ? gold : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? gold : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Build Prompt

    private func buildPrompt() -> String {
        var parts: [String] = []

        // Content type
        switch contentType {
        case "fiction": parts.append("Find me fiction content.")
        case "nonfiction": parts.append("Find me non-fiction content.")
        case "either": parts.append("Find me content — fiction or non-fiction.")
        default: break
        }

        // Topics
        let topicLabels: [String: String] = [
            "science_tech": "Science/Tech", "philosophy": "Philosophy/Ideas",
            "history": "History", "psychology": "Psychology",
            "business": "Business/Finance", "self_help": "Self-improvement",
            "mystery": "Mystery/Thriller", "scifi": "Sci-Fi/Fantasy",
            "biography": "Biography/Memoir", "politics": "Politics/Society",
        ]
        if !selectedTopics.isEmpty {
            let names = selectedTopics.compactMap { topicLabels[$0] }
            parts.append("Topics: \(names.joined(separator: ", ")).")
        }

        // Reading time
        switch readingTime {
        case "quick": parts.append("I want quick reads under 1 hour.")
        case "medium": parts.append("I want medium-length reads, around 1-5 hours.")
        case "deep": parts.append("I want deep dives, 5+ hours of reading.")
        default: break
        }

        // Format
        let formatLabels: [String: String] = ["epub": "ePub", "pdf": "PDF", "web": "articles/websites"]
        if !selectedFormats.isEmpty {
            let names = selectedFormats.compactMap { formatLabels[$0] }
            parts.append("Format: \(names.joined(separator: ", ")).")
        }

        // Cost
        switch cost {
        case "free": parts.append("Free content only.")
        case "paid": parts.append("Include paid content too.")
        default: break
        }

        // Discovery
        switch discovery {
        case "popular": parts.append("Focus on popular picks and bestsellers.")
        case "hidden": parts.append("I prefer hidden gems and under-the-radar finds.")
        case "mix": parts.append("Mix of popular and hidden gems.")
        default: break
        }

        // Custom
        let custom = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            parts.append(custom)
        }

        // Digital-only constraint
        parts.append("IMPORTANT: Only recommend digital content available online (ePub, PDF, web articles). No physical books.")

        return parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private func singleBinding(_ binding: Binding<String?>) -> Binding<Set<String>> {
        Binding<Set<String>>(
            get: { binding.wrappedValue.map { [$0] } ?? [] },
            set: { binding.wrappedValue = $0.first }
        )
    }
}
