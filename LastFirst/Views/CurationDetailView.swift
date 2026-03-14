import SwiftUI

struct CurationDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var readerCoordinator: ReaderCoordinator
    @Environment(\.dismiss) private var dismiss

    let readingList: ReadingList

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedItemIds: [UUID] = []
    @State private var previewContext: BookPreviewContext?
    @State private var showItemPicker = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var displayItems: [LibraryItem] {
        let ids = isEditing ? editedItemIds : readingList.itemIds
        return ids.compactMap { id in
            appState.library.first(where: { $0.id == id })
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(displayItems) { item in
                    coverCell(item: item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .navigationTitle(isEditing ? "" : readingList.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isEditing {
                    TextField("Curation name", text: $editedName)
                        .font(.hedvigLettersSerif(18))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    HStack(spacing: 12) {
                        Button {
                            showItemPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                        }

                        Button("Save") {
                            saveEdits()
                        }
                        .font(.rethinkSans(15, weight: .bold))
                    }
                } else {
                    Button("Edit") {
                        enterEditMode()
                    }
                    .font(.rethinkSans(15, weight: .medium))
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if isEditing {
                    Button {
                        discardEdits()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
        }
        .sheet(item: $previewContext) { context in
            BookPreviewSheet(
                items: context.items,
                initialIndex: context.initialIndex
            )
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(0)
            .presentationBackground(.clear)
            .environmentObject(appState)
            .environmentObject(readerCoordinator)
        }
        .sheet(isPresented: $showItemPicker) {
            itemPickerSheet
        }
    }

    // MARK: - Cover Cell

    private func coverCell(item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(
                coverImageData: appState.getCoverImage(for: item.documentId),
                coverURL: item.curatedCoverURL,
                title: item.title,
                iconName: item.coverIconName,
                size: CGSize(width: 160, height: 233),
                flexibleAspectRatio: true
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .frame(maxWidth: .infinity)
            .onTapGesture {
                if isEditing {
                    // In edit mode, remove item
                    withAnimation {
                        editedItemIds.removeAll { $0 == item.id }
                    }
                } else {
                    let items = displayItems
                    if let idx = items.firstIndex(where: { $0.id == item.id }) {
                        previewContext = BookPreviewContext(items: items, initialIndex: idx)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    Button {
                        withAnimation {
                            editedItemIds.removeAll { $0 == item.id }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                            .background(Circle().fill(.white).padding(2))
                    }
                    .offset(x: 6, y: -6)
                }
            }

            Text(item.title)
                .font(.rethinkSans(13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let author = item.author, !author.isEmpty {
                Text(author)
                    .font(.rethinkSans(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Item Picker Sheet

    private var itemPickerSheet: some View {
        NavigationStack {
            let available = appState.library.filter { !editedItemIds.contains($0.id) }
            List(available) { item in
                Button {
                    editedItemIds.append(item.id)
                } label: {
                    HStack(spacing: 12) {
                        BookCoverView(
                            coverImageData: appState.getCoverImage(for: item.documentId),
                            coverURL: item.curatedCoverURL,
                            title: item.title,
                            iconName: item.coverIconName,
                            size: CGSize(width: 40, height: 58),
                            cornerRadius: 4
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.rethinkSans(15, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let author = item.author, !author.isEmpty {
                                Text(author)
                                    .font(.rethinkSans(13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showItemPicker = false }
                }
            }
        }
    }

    // MARK: - Edit Actions

    private func enterEditMode() {
        editedName = readingList.name
        editedItemIds = readingList.itemIds
        isEditing = true
    }

    private func saveEdits() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.updateReadingList(id: readingList.id, name: trimmed, itemIds: editedItemIds)
        isEditing = false
    }

    private func discardEdits() {
        editedName = readingList.name
        editedItemIds = readingList.itemIds
        isEditing = false
    }
}
