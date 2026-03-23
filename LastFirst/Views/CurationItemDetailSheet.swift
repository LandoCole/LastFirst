import SwiftUI

struct CurationItemDetailSheet: View {
    let item: CurationItem
    let userId: UUID?
    var onSave: ((CurationItem) -> Void)?
    var curatorModel: String = "claude"

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @State private var isSaved = false
    @State private var showSummarizationSheet = false

    var body: some View {
        VStack(spacing: 20) {
            // Cover
            BookCoverView(
                coverImageData: nil,
                coverURL: coverURL,
                title: item.displayTitle,
                iconName: coverIcon,
                width: 160,
                cornerRadius: 8,
                contentType: coverContentType
            )
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .padding(.top, 24)

            // Title & Author
            VStack(spacing: 6) {
                Text(item.displayTitle)
                    .font(.hedvigLettersSerif(22))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let author = item.displayAuthor, !author.isEmpty {
                    Text(author)
                        .font(.rethinkSans(15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            // Source link
            if let sourceURL = itemSourceURL {
                Link(destination: sourceURL) {
                    HStack(spacing: 4) {
                        Text(sourceURL.host ?? sourceURL.absoluteString)
                            .font(.rethinkSans(13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
            }

            // Metadata row
            HStack(spacing: 8) {
                if let fileType = item.content?.fileType?.uppercased() ?? itemTypeLabel {
                    Text(fileType)
                        .font(.rethinkSans(13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let minutes = item.content?.estimatedReadMinutes {
                    Text("\u{00B7}")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("\(minutes) min read")
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                } else if let wc = item.content?.wordCount {
                    Text("\u{00B7}")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("\(wc / 250) min read")
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                }
            }

            // Summary
            if let summary = item.displaySummary, !summary.isEmpty {
                Text(summary)
                    .font(.rethinkSans(14))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Agent note
            if let note = item.agentNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(note)
                        .font(.rethinkSans(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Interaction buttons
            HStack(spacing: 24) {
                interactionButton(icon: "hand.thumbsup", kind: "like")
                interactionButton(icon: "hand.thumbsdown", kind: "dislike")
                interactionButton(icon: "bookmark", kind: "bookmark")
            }

            // Availability badge
            if let availability = effectiveAvailability, availability != "full_text" {
                HStack(spacing: 6) {
                    Image(systemName: availabilityIcon(availability))
                        .font(.system(size: 11))
                    Text(availabilityLabel(availability))
                        .font(.rethinkSans(12, weight: .medium))
                }
                .foregroundStyle(availabilityColor(availability))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(availabilityColor(availability).opacity(0.12))
                .clipShape(Capsule())
            }

            // Action buttons
            if effectiveAvailability == "external_purchase", let urlString = item.externalUrl ?? item.content?.sourceUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Text("Open in Store")
                        .font(.rethinkSans(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            } else {
                VStack(spacing: 10) {
                    // Read Full Text / Save to Library
                    HStack(spacing: 10) {
                        if hasReadableContent {
                            Button {
                                let libraryItem = saveAndGetItem()
                                readerCoordinator.openItem(libraryItem, appState: appState)
                                dismiss()
                            } label: {
                                Text("Read Full Text")
                                    .font(.rethinkSans(15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Button {
                                showSummarizationSheet = true
                            } label: {
                                Text("Summarize")
                                    .font(.rethinkSans(15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    Button {
                        onSave?(item)
                        isSaved = true
                    } label: {
                        Text(isSaved ? "Saved" : "Save to Library")
                            .font(.rethinkSans(hasReadableContent ? 14 : 16, weight: .semibold))
                            .foregroundStyle(hasReadableContent ? Color.secondary : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, hasReadableContent ? 10 : 14)
                            .background(isSaved ? Color.gray : (hasReadableContent ? Color.clear : Color.accentColor))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSaved)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .sheet(isPresented: $showSummarizationSheet) {
            SummarizationSheet(
                text: summarizableText,
                title: item.displayTitle,
                sourceUrl: itemSourceURL,
                model: curatorModel
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var hasReadableContent: Bool {
        item.extractedText != nil || item.externalUrl != nil || item.content?.sourceUrl != nil
    }

    private var summarizableText: String {
        item.extractedText ?? item.displaySummary ?? ""
    }

    @discardableResult
    private func saveAndGetItem() -> LibraryItem {
        let libraryItem = appState.addCuratedItem(item)
        isSaved = true
        Task {
            try? await SupabaseManager.shared.markCurationItemSaved(itemId: item.id)
            if let contentId = item.contentId,
               let userId {
                try? await SupabaseManager.shared.postInteraction(
                    userId: userId,
                    contentId: contentId,
                    kind: "bookmark"
                )
            }
        }
        return libraryItem
    }

    private var itemSourceURL: URL? {
        if let urlString = item.externalUrl ?? item.content?.sourceUrl {
            return URL(string: urlString)
        }
        return nil
    }

    private var coverURL: URL? {
        if let urlString = item.content?.coverUrl {
            return URL(string: urlString)
        }
        return nil
    }

    private var coverIcon: String {
        switch item.content?.fileType ?? item.itemType {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.fill"
        default: return "newspaper.fill"
        }
    }

    private var coverContentType: CoverContentType {
        switch item.displayFileType {
        case "epub": return .epub
        case "pdf": return .pdf
        default: return .article
        }
    }

    private var itemTypeLabel: String? {
        let type = item.itemType
        guard type != "content" else { return nil }
        return type.uppercased()
    }

    private var effectiveAvailability: String? {
        item.content?.availability ?? (item.itemType == "external_link" || item.itemType == "book" ? "external_purchase" : nil)
    }

    private func availabilityIcon(_ availability: String) -> String {
        switch availability {
        case "downloadable": return "arrow.down.circle"
        case "external_purchase": return "cart"
        case "paywalled": return "lock"
        default: return "doc.text"
        }
    }

    private func availabilityLabel(_ availability: String) -> String {
        switch availability {
        case "downloadable": return "Download Available"
        case "external_purchase": return "Purchase Required"
        case "paywalled": return "Subscription Required"
        default: return "Available"
        }
    }

    private func availabilityColor(_ availability: String) -> Color {
        switch availability {
        case "downloadable": return .blue
        case "external_purchase": return .orange
        case "paywalled": return .red
        default: return .green
        }
    }

    private func interactionButton(icon: String, kind: String) -> some View {
        Button {
            guard let contentId = item.contentId, let userId else { return }
            Task {
                try? await SupabaseManager.shared.postInteraction(
                    userId: userId,
                    contentId: contentId,
                    kind: kind
                )
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
    }
}
