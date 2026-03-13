import SwiftUI

struct CurationFilterBar: View {
    @Binding var filter: CurationFilter
    @Environment(\.dismiss) private var dismiss

    private let genres = ["Fiction", "Non-Fiction", "Science", "Technology", "Philosophy", "History", "Business", "Self-Help", "Biography", "Poetry"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Search
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search")
                            .font(.rethinkSans(14, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("Search titles & summaries...", text: Binding(
                            get: { filter.searchQuery ?? "" },
                            set: { filter.searchQuery = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.rethinkSans(15))
                        .textFieldStyle(.roundedBorder)
                    }

                    // Genre
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Genre")
                            .font(.rethinkSans(14, weight: .medium))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(genres, id: \.self) { genre in
                                    genreChip(genre)
                                }
                            }
                        }
                    }

                    // Length
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Length")
                            .font(.rethinkSans(14, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            lengthButton("Short", maxMinutes: 15)
                            lengthButton("Medium", maxMinutes: 60)
                            lengthButton("Long", maxMinutes: nil)
                        }
                    }

                    // Author
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Author")
                            .font(.rethinkSans(14, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("Filter by author...", text: Binding(
                            get: { filter.author ?? "" },
                            set: { filter.author = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.rethinkSans(15))
                        .textFieldStyle(.roundedBorder)
                    }

                    // Clear All
                    if filter.isActive {
                        Button {
                            filter.clearAll()
                        } label: {
                            Text("Clear All")
                                .font(.rethinkSans(14, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func genreChip(_ genre: String) -> some View {
        let isSelected = filter.genre == genre
        return Button {
            filter.genre = isSelected ? nil : genre
        } label: {
            Text(genre)
                .font(.rethinkSans(13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary : Color(.systemGray6))
                .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                .clipShape(Capsule())
        }
    }

    private func lengthButton(_ label: String, maxMinutes: Int?) -> some View {
        let isSelected: Bool = {
            switch label {
            case "Short": return filter.maxLengthMinutes == 15
            case "Medium": return filter.maxLengthMinutes == 60
            case "Long": return filter.maxLengthMinutes == nil && filter.genre != nil // only show as selected if actively set
            default: return false
            }
        }()

        return Button {
            if isSelected {
                filter.maxLengthMinutes = nil
            } else {
                filter.maxLengthMinutes = maxMinutes
            }
        } label: {
            Text(label)
                .font(.rethinkSans(13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(filter.maxLengthMinutes == maxMinutes ? Color.primary : Color(.systemGray6))
                .foregroundStyle(filter.maxLengthMinutes == maxMinutes ? Color(.systemBackground) : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
