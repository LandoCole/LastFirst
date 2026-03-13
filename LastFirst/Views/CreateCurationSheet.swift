import SwiftUI

struct CreateCurationSheet: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CurationCreationViewModel()
    @Environment(\.dismiss) private var dismiss

    var editingList: ReadingList?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Name input
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Collection name...", text: $vm.name)
                            .font(.hedvigLettersSerif(24))
                            .textFieldStyle(.plain)

                        Text("\(vm.selectedItemIds.count) items selected")
                            .font(.rethinkSans(13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Search + bulk actions
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search library...", text: $vm.searchText)
                                .font(.rethinkSans(15))
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack {
                            Button {
                                if vm.selectedItemIds.isEmpty {
                                    vm.selectAll(from: appState.library)
                                } else {
                                    vm.deselectAll()
                                }
                            } label: {
                                Text(vm.selectedItemIds.isEmpty ? "Select All" : "Deselect All")
                                    .font(.rethinkSans(13, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 20)

                    // Item list
                    let filtered = vm.filteredItems(from: appState.library)
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .navigationTitle(editingList != nil ? "Edit Collection" : "New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text(editingList != nil ? "Save Changes" : "Create Collection")
                            .font(.rethinkSans(16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.selectedItemIds.isEmpty)

                    if editingList != nil {
                        Button(role: .destructive) {
                            if let id = vm.editingListId {
                                appState.deleteReadingList(id)
                            }
                            dismiss()
                        } label: {
                            Text("Delete Collection")
                                .font(.rethinkSans(14, weight: .medium))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .onAppear {
            if let list = editingList {
                vm.loadExisting(list: list, library: appState.library)
            }
        }
        .onChange(of: vm.name) {
            if vm.editingListId == nil {
                vm.localSuggest(from: appState.library)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Item Row

    private func itemRow(_ item: LibraryItem) -> some View {
        let isSelected = vm.selectedItemIds.contains(item.id)
        return Button {
            if isSelected {
                vm.selectedItemIds.remove(item.id)
            } else {
                vm.selectedItemIds.insert(item.id)
            }
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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save

    private func save() {
        let trimmed = vm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let listId = vm.editingListId {
            appState.updateReadingList(id: listId, name: trimmed, itemIds: Array(vm.selectedItemIds))
        } else {
            let list = appState.addReadingList(name: trimmed)
            for itemId in vm.selectedItemIds {
                appState.addItemToList(itemId, listId: list.id)
            }
        }
    }
}
