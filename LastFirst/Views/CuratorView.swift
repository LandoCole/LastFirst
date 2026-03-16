import SwiftUI

enum CuratorAIModel: String, CaseIterable {
    case chatGPT = "ChatGPT"
    case claude = "Claude"
    case gemini = "Gemini"
}

struct CuratorView: View {
    @Binding var inputText: String
    @FocusState private var isInputFocused: Bool
    @State private var selectedModel: CuratorAIModel = .claude
    @State private var showHistory = false
    @State private var showCuratedPane = false
    @State private var selectedDetailItem: CurationItem?
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel: CuratorViewModel

    private let quotes = [
        "An expert in anything was once a beginner\n—Helen Hayes",
        "A reader lives a thousand lives before he dies\n—George R.R. Martin",
        "The more that you read, the more things you will know\n—Dr. Seuss",
        "Reading is to the mind what exercise is to the body\n—Joseph Addison"
    ]

    init(inputText: Binding<String>, userId: UUID) {
        self._inputText = inputText
        self._viewModel = StateObject(wrappedValue: CuratorViewModel(userId: userId))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 34)

            if viewModel.messages.isEmpty && viewModel.curationItems.isEmpty {
                Spacer()
                quoteView
                Spacer()
            } else {
                messageList
            }

            // Error banner
            if let error = viewModel.error {
                Text(error)
                    .font(.rethinkSans(12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            // Curated pane button
            if !viewModel.curationItems.isEmpty {
                Button {
                    showCuratedPane = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 13))
                        Text("Curated (\(viewModel.curationItems.count))")
                            .font(.rethinkSans(13, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                }
            }

            inputBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showHistory) {
            CuratorHistoryView(curations: viewModel.pastCurations) { curationId in
                Task { await viewModel.loadCuration(id: curationId) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedDetailItem) { item in
            CurationItemDetailSheet(
                item: item,
                userId: authVM.currentUser?.id,
                onSave: { curationItem in
                    appState.addCuratedItem(curationItem)
                    Task {
                        try? await SupabaseManager.shared.markCurationItemSaved(itemId: curationItem.id)
                        if let contentId = curationItem.contentId,
                           let userId = authVM.currentUser?.id {
                            try? await SupabaseManager.shared.postInteraction(
                                userId: userId,
                                contentId: contentId,
                                kind: "bookmark"
                            )
                        }
                    }
                },
                curatorModel: selectedModel.rawValue.lowercased()
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCuratedPane) {
            curatedPaneSheet
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                Task { await viewModel.loadPastCurations() }
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
            }
            .nativeGlassButton(shape: .circle)

            Spacer()

            Menu {
                ForEach(CuratorAIModel.allCases, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        if model == selectedModel {
                            Label(model.rawValue, systemImage: "checkmark")
                        } else {
                            Text(model.rawValue)
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Curator")
                            .font(.hedvigLettersSerif(24))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text(selectedModel.rawValue)
                        .font(.hedvigLettersSerif(12))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                viewModel.startNewConversation()
                inputText = ""
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
            }
            .nativeGlassButton(shape: .circle)
        }
    }

    // MARK: - Quote

    private var quoteView: some View {
        Text(quotes.first ?? "")
            .font(.hedvigLettersSerif(12))
            .foregroundStyle(Color(hex: "BCB8B1"))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                            .id(message.id)

                        // Inline card stack for items added by this assistant message
                        if message.role == "assistant",
                           let items = viewModel.messageItems[message.id],
                           !items.isEmpty {
                            CurationCardStack(items: items, selectedDetailItem: $selectedDetailItem)
                                .padding(.horizontal, 16)
                        }
                    }

                    if viewModel.isLoading {
                        if let plan = viewModel.researchPlan {
                            CuratorPlanView(plan: plan)
                                .id("plan")
                        }

                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(viewModel.statusMessage ?? "Thinking...")
                                .font(.rethinkSans(12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .id("loading")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation {
                    if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.activities.count) {
                withAnimation {
                    if viewModel.isLoading {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.researchPlan) {
                withAnimation {
                    if viewModel.isLoading {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: CurationMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            Text(message.content)
                .font(.rethinkSans(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == "user"
                        ? Color.warmForeground
                        : Color.warmBackground
                )
                .foregroundStyle(message.role == "user" ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role != "user" { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Curated Pane Sheet

    private var curatedPaneSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.curationItems) { item in
                    curatedPaneRow(item)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Curated Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showCuratedPane = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save All") {
                        viewModel.selectAll()
                        Task { await viewModel.saveSelectedToLibrary(appState: appState) }
                        showCuratedPane = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func curatedPaneRow(_ item: CurationItem) -> some View {
        let isSelected = viewModel.selectedItemIds.contains(item.id)
        let coverURL: URL? = {
            if let urlString = item.content?.coverUrl {
                return URL(string: urlString)
            }
            return nil
        }()
        let iconName: String = {
            switch item.content?.fileType ?? item.itemType {
            case "epub": return "book.closed.fill"
            case "pdf": return "doc.fill"
            default: return "newspaper.fill"
            }
        }()

        return HStack(spacing: 12) {
            BookCoverView(
                coverImageData: nil,
                coverURL: coverURL,
                title: item.displayTitle,
                iconName: iconName,
                size: CGSize(width: 60, height: 87),
                cornerRadius: 4
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.rethinkSans(14, weight: .semibold))
                    .lineLimit(2)

                if let author = item.displayAuthor, !author.isEmpty {
                    Text(author)
                        .font(.rethinkSans(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let note = item.agentNote, !note.isEmpty {
                    Text(note)
                        .font(.rethinkSans(11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleSelection(item.id)
        }
        .contextMenu {
            Button {
                appState.addCuratedItem(item)
                Task {
                    try? await SupabaseManager.shared.markCurationItemSaved(itemId: item.id)
                }
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }

            if !appState.readingLists.isEmpty {
                Menu("Add to List...") {
                    ForEach(appState.readingLists) { list in
                        Button {
                            let libraryItem = appState.addCuratedItem(item)
                            appState.addItemToList(libraryItem.id, listId: list.id)
                        } label: {
                            Label(list.name, systemImage: "list.bullet")
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.selectedItemIds.remove(item.id)
            } label: {
                Label("Remove", systemImage: "xmark")
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                // Future: attachment action
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "B08D57"))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            ZStack(alignment: .trailing) {
                TextField("Ask Curator", text: $inputText)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.trailing, inputText.isEmpty ? 0 : 28)
                    .frame(height: 36)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 12)
                }
            }
            .glassStyle(shape: .pill)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.isEmpty || viewModel.isLoading
                            ? Color.secondary
                            : Color.accentColor
                    )
            }
            .disabled(inputText.isEmpty || viewModel.isLoading)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task {
            await viewModel.sendMessage(text, model: selectedModel)
        }
    }
}
