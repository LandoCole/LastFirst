import SwiftUI

struct CuratorHistoryView: View {
    let curations: [Curation]
    var onSelect: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if curations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No past conversations")
                            .font(.rethinkSans(15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(curations) { curation in
                        Button {
                            onSelect?(curation.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(curation.title)
                                        .font(.hedvigLettersSerif(16))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    if let date = curation.createdAt {
                                        Text(date, style: .date)
                                            .font(.rethinkSans(12))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if curation.type == "daily" {
                                    Text("Daily")
                                        .font(.rethinkSans(11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.warmBackground)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
