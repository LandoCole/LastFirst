import SwiftUI
import MarkdownUI

enum CuratorAIModel: String, CaseIterable {
    case claude = "Claude"
    case gpt4o = "GPT-5.4 Nano"
    case gemini = "Gemini 3.1 Flash-Lite"

    var apiValue: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .gpt4o: return "gpt-5.4-nano"
        case .gemini: return "gemini-3.1-flash-lite"
        }
    }
}

struct CuratorView: View {
    @Binding var inputText: String
    @FocusState private var isInputFocused: Bool
    @State private var selectedModel: CuratorAIModel = .claude
    @State private var showHistory = false
    @State private var showCuratedPane = false
    @State private var curationPreviewContext: CurationPreviewContext?
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

    private var topSafeArea: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
            let window = windowScene.windows.first else { return 59 }
        return window.safeAreaInsets.top
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, topSafeArea + 16)

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

            inputBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            if value.translation.height > 30
                                && abs(value.translation.height) > abs(value.translation.width) {
                                isInputFocused = false
                            }
                        }
                )
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showHistory) {
            CuratorHistoryView(curations: viewModel.pastCurations) { curationId in
                Task { await viewModel.loadCuration(id: curationId) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $curationPreviewContext) { context in
            CurationPreviewSheet(
                items: context.items,
                initialIndex: context.initialIndex,
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
                curatorModel: selectedModel.apiValue
            )
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
                        Label(model.rawValue, systemImage: selectedModel == model ? "checkmark" : "")
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text("Curator")
                        .font(.hedvigLettersSerif(24))
                    HStack(spacing: 4) {
                        Text(selectedModel.rawValue)
                            .font(.hedvigLettersSerif(12))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

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
                            CurationCardStack(items: items) { tappedItem in
                                if let idx = items.firstIndex(where: { $0.id == tappedItem.id }) {
                                    curationPreviewContext = CurationPreviewContext(items: items, initialIndex: idx)
                                } else {
                                    curationPreviewContext = CurationPreviewContext(items: [tappedItem])
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Clarification questions (shown after assistant intro)
                    if !viewModel.clarificationQuestions.isEmpty {
                        ClarificationQuestionsView(
                            questions: viewModel.clarificationQuestions,
                            selections: $viewModel.clarificationSelections,
                            onSubmit: {
                                Task {
                                    await viewModel.submitClarificationSelections(model: selectedModel)
                                }
                            },
                            canSubmit: viewModel.canSubmitClarification
                        )
                        .id("clarification")
                        .transition(.opacity)
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
            .scrollDismissesKeyboard(.interactively)
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
            .onChange(of: viewModel.clarificationQuestions.count) {
                if !viewModel.clarificationQuestions.isEmpty {
                    withAnimation {
                        proxy.scrollTo("clarification", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: CurationMessage) -> some View {
        Group {
            if message.role == "user" {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.content)
                        .font(.rethinkSans(14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.warmForeground)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)
            } else {
                Markdown(message.content)
                    .markdownTextStyle(\.text) {
                        FontSize(.em(0.875))
                    }
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Curated Pane Sheet

    @State private var showSaveToCollection = false
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""

    private var curatedPaneSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(viewModel.curationItems) { item in
                        curatedPaneRow(item)
                    }
                }
                .listStyle(.plain)

                if !viewModel.selectedItemIds.isEmpty {
                    Button {
                        showSaveToCollection = true
                    } label: {
                        Text("Save to Collection")
                            .font(.rethinkSans(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "463F3A"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Curated Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showCuratedPane = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.selectedItemIds.count == viewModel.curationItems.count ? "Deselect All" : "Select All") {
                        if viewModel.selectedItemIds.count == viewModel.curationItems.count {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAll()
                        }
                    }
                }
            }
            .confirmationDialog("Save to Collection", isPresented: $showSaveToCollection, titleVisibility: .visible) {
                ForEach(appState.readingLists) { list in
                    Button(list.name) {
                        saveSelectedToCollection(listId: list.id)
                    }
                }
                Button("New Collection...") {
                    showNewCollectionAlert = true
                }
                Button("Library Only") {
                    saveSelectedToLibraryOnly()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Collection", isPresented: $showNewCollectionAlert) {
                TextField("Collection name", text: $newCollectionName)
                Button("Create") {
                    guard !newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let list = appState.addReadingList(name: newCollectionName.trimmingCharacters(in: .whitespaces))
                    saveSelectedToCollection(listId: list.id)
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func saveSelectedToCollection(listId: UUID) {
        let selected = viewModel.curationItems.filter { viewModel.selectedItemIds.contains($0.id) }
        for item in selected {
            let libraryItem = appState.addCuratedItem(item)
            appState.addItemToList(libraryItem.id, listId: listId)
            Task {
                try? await SupabaseManager.shared.markCurationItemSaved(itemId: item.id)
            }
        }
        viewModel.selectedItemIds.removeAll()
        showCuratedPane = false
    }

    private func saveSelectedToLibraryOnly() {
        let selected = viewModel.curationItems.filter { viewModel.selectedItemIds.contains($0.id) }
        for item in selected {
            _ = appState.addCuratedItem(item)
            Task {
                try? await SupabaseManager.shared.markCurationItemSaved(itemId: item.id)
            }
        }
        viewModel.selectedItemIds.removeAll()
        showCuratedPane = false
    }

    private func curatedPaneRow(_ item: CurationItem) -> some View {
        let isSelected = viewModel.selectedItemIds.contains(item.id)
        let coverURL: URL? = item.displayImageUrl
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
                showCuratedPane = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "463F3A"))
                        .frame(width: 36, height: 36)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .topTrailing) {
                    if viewModel.curationItems.count > 0 {
                        Text("\(viewModel.curationItems.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color(hex: "B17E25"))
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)

            if !viewModel.clarificationQuestions.isEmpty {
                Text("Select options above to refine your search")
                    .font(.rethinkSans(12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            } else {

            HStack(spacing: 6) {
                TextField("Ask Curator", text: $inputText)
                    .font(.system(size: 14))
                    .padding(.leading, 14)
                    .frame(height: 36)
                    .focused($isInputFocused)
                    .tint(Color(hex: "463F3A"))
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(inputText.isEmpty || viewModel.isLoading
                                    ? Color.secondary
                                    : Color(hex: "B17E25"))
                        )
                }
                .disabled(inputText.isEmpty || viewModel.isLoading)
                .padding(.trailing, 4)
            }
            .glassStyle(shape: .pill)

            } // end else (not clarification)
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
