import Foundation
import SwiftUI

struct CuratorActivity: Identifiable, Equatable {
    let id: UUID
    let icon: String
    let message: String
    let detail: String?
    let timestamp: Date

    static func == (lhs: CuratorActivity, rhs: CuratorActivity) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class CuratorViewModel: ObservableObject {
    @Published var messages: [CurationMessage] = []
    @Published var curationItems: [CurationItem] = []
    @Published var activeCurationId: UUID?
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var error: String?
    @Published var selectedItemIds: Set<UUID> = []
    @Published var pastCurations: [Curation] = []
    @Published var activities: [CuratorActivity] = []
    @Published var researchPlan: CuratorResearchPlan?
    /// Maps assistant message ID → items added in that response
    @Published var messageItems: [UUID: [CurationItem]] = [:]

    private let userId: UUID
    private var pollingTask: Task<Void, Never>?
    private var seenToolMessageIds: Set<UUID> = []

    init(userId: UUID) {
        self.userId = userId
    }

    // MARK: - Send Message

    func sendMessage(_ text: String, model: CuratorAIModel = .claude) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Optimistically add user message
        let userMessage = CurationMessage(
            id: UUID(),
            curationId: activeCurationId ?? UUID(),
            role: "user",
            content: trimmed,
            createdAt: Date()
        )
        messages.append(userMessage)

        isLoading = true
        statusMessage = "Curator is thinking..."
        activities = []
        researchPlan = nil
        seenToolMessageIds = []
        error = nil

        // Start polling for tool status messages
        startActivityPolling()

        do {
            let response = try await SupabaseManager.shared.sendCuratorMessage(
                curationId: activeCurationId,
                message: trimmed,
                userId: userId,
                model: model.rawValue.lowercased()
            )

            // Update curation ID (may be newly created)
            activeCurationId = response.curationId

            if let directResponse = response.response {
                // SIMPLE: response came back inline
                let assistantMessage = CurationMessage(
                    id: UUID(),
                    curationId: response.curationId,
                    role: "assistant",
                    content: directResponse,
                    createdAt: Date()
                )
                messages.append(assistantMessage)

                // Refresh curation items and track which belong to this message
                if let itemsAdded = response.itemsAdded, itemsAdded > 0 {
                    let previousIds = Set(curationItems.map(\.id))
                    await loadCurationItems()
                    let newItems = curationItems.filter { !previousIds.contains($0.id) }
                    if !newItems.isEmpty {
                        messageItems[assistantMessage.id] = newItems
                    }
                }

                stopActivityPolling()
                isLoading = false
                statusMessage = nil
            } else {
                // MODERATE/COMPLEX: response will come via background processing
                // Keep polling — pollActivities() picks up agent statuses
                // Poll curations.status until 'ready', then fetch assistant message
                await pollUntilReady(curationId: response.curationId)
            }
        } catch {
            self.error = error.localizedDescription
            // Remove the optimistic user message on failure
            messages.removeLast()
            stopActivityPolling()
            isLoading = false
            statusMessage = nil
        }
    }

    // MARK: - Poll Until Ready (Multi-Agent)

    private func pollUntilReady(curationId: UUID) async {
        let maxPollDuration: TimeInterval = 300 // 5 minute timeout
        let startTime = Date()

        while !Task.isCancelled {
            // Timeout guard
            if Date().timeIntervalSince(startTime) > maxPollDuration {
                error = "Research timed out. Please try again."
                isLoading = false
                statusMessage = nil
                stopActivityPolling()
                return
            }

            // Poll tool messages for progress (existing)
            await pollActivities()

            // Check if curation is ready
            if let curation = try? await SupabaseManager.shared.fetchCuration(id: curationId) {
                if curation.status == "ready" {
                    // Fetch the final assistant message + items
                    if let msgs = try? await SupabaseManager.shared.fetchCurationMessages(curationId: curationId) {
                        if let lastAssistant = msgs.last(where: { $0.role == "assistant" }) {
                            messages.append(lastAssistant)
                        }
                    }
                    await loadCurationItems()
                    rebuildMessageItems()
                    isLoading = false
                    statusMessage = nil
                    stopActivityPolling()
                    return
                }

                if curation.status == "error" {
                    error = curation.errorMessage ?? "Research failed"
                    isLoading = false
                    statusMessage = nil
                    stopActivityPolling()
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    // MARK: - Activity Polling

    private func startActivityPolling() {
        pollingTask = Task { [weak self] in
            // Brief delay to let the edge function create the curation
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard self != nil else { return }

            while !Task.isCancelled {
                await self?.pollActivities()
                try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s interval
                guard self != nil else { return }
            }
        }
    }

    private func stopActivityPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollActivities() async {
        // Resolve curation ID — use active if known, otherwise look up the latest researching one
        var curationId = activeCurationId
        if curationId == nil {
            curationId = try? await SupabaseManager.shared.fetchLatestResearchingCuration(userId: userId)
            if let curationId {
                activeCurationId = curationId
            }
        }

        guard let curationId else { return }

        do {
            let toolMessages = try await SupabaseManager.shared.fetchToolMessages(curationId: curationId)
            let newMessages = toolMessages.filter { !seenToolMessageIds.contains($0.id) }

            for msg in newMessages {
                seenToolMessageIds.insert(msg.id)
                parseToolMessage(msg)
            }
        } catch {
            // Polling errors are non-critical
        }
    }

    private func parseToolMessage(_ message: CurationMessage) {
        guard let data = message.content.data(using: .utf8) else { return }

        // Try new status protocol first
        if let status = try? JSONDecoder().decode(CuratorStatusMessage.self, from: data) {
            handleStatusMessage(status)
            return
        }

        // Legacy fallback: old {tool, status} format
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String,
              let statusText = json["status"] as? String else {
            return
        }

        let icon: String
        switch tool {
        case "search_content": icon = "magnifyingglass"
        case "search_web": icon = "globe"
        case "fetch_url": icon = "doc.text.magnifyingglass"
        case "create_curation_item": icon = "plus.circle.fill"
        case "get_user_reading_history": icon = "clock"
        case "get_content_details": icon = "info.circle"
        case "ingest_url": icon = "arrow.down.circle"
        case "thinking": icon = "brain"
        case "done": icon = "checkmark.circle"
        default: icon = "gearshape"
        }

        let activity = CuratorActivity(
            id: message.id,
            icon: icon,
            message: statusText,
            detail: json["detail"] as? String,
            timestamp: message.createdAt ?? Date()
        )
        withAnimation(.easeOut(duration: 0.3)) {
            activities.append(activity)
            statusMessage = activity.message
        }
    }

    private func handleStatusMessage(_ status: CuratorStatusMessage) {
        switch status.type {
        case .plan:
            guard let planSteps = status.plan else { return }
            let steps = planSteps.map { CuratorPlanStep(label: $0.label, description: $0.description) }
            withAnimation(.easeOut(duration: 0.3)) {
                researchPlan = CuratorResearchPlan(steps: steps)
            }

        case .stepStart:
            guard let idx = status.stepIndex else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if var plan = researchPlan, idx < plan.steps.count {
                    plan.steps[idx].state = .active
                    plan.currentStepIndex = idx
                    researchPlan = plan
                }
                statusMessage = status.message
            }

        case .stepProgress:
            statusMessage = status.message

        case .stepComplete:
            guard let idx = status.stepIndex else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if var plan = researchPlan, idx < plan.steps.count {
                    plan.steps[idx].state = .complete
                    plan.steps[idx].finding = status.finding
                    researchPlan = plan
                }
                statusMessage = status.message
            }

        case .finding:
            guard let idx = status.stepIndex else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if var plan = researchPlan, idx < plan.steps.count {
                    plan.steps[idx].finding = status.finding ?? status.detail
                    researchPlan = plan
                }
            }

        case .error:
            statusMessage = status.message

        case .agentSpawned:
            withAnimation(.easeOut(duration: 0.3)) {
                if let total = status.totalAgents {
                    statusMessage = "Launching \(total) research agents..."
                }
                // Initialize agents list in research plan
                if researchPlan == nil {
                    researchPlan = CuratorResearchPlan()
                }
            }

        case .agentProgress:
            if let role = status.agentRole, let taskId = status.agentTaskId {
                withAnimation(.easeOut(duration: 0.3)) {
                    if researchPlan == nil {
                        researchPlan = CuratorResearchPlan()
                    }
                    if let idx = researchPlan?.agents.firstIndex(where: { $0.id.uuidString == taskId }) {
                        researchPlan?.agents[idx].state = .active
                    } else {
                        researchPlan?.agents.append(AgentProgress(
                            id: UUID(uuidString: taskId) ?? UUID(),
                            role: role,
                            state: .active
                        ))
                    }
                    statusMessage = status.message
                }
            }

        case .agentComplete:
            if let taskId = status.agentTaskId,
               let idx = researchPlan?.agents.firstIndex(where: { $0.id.uuidString == taskId }) {
                withAnimation(.easeOut(duration: 0.3)) {
                    researchPlan?.agents[idx].state = .complete
                    researchPlan?.agents[idx].finding = status.finding
                    statusMessage = status.message
                }
            }

        case .synthesisStart:
            withAnimation(.easeOut(duration: 0.3)) {
                statusMessage = "Evaluating and ranking findings..."
            }
        }
    }

    // MARK: - Load Existing Curation

    func loadCuration(id: UUID) async {
        activeCurationId = id
        isLoading = true
        defer { isLoading = false }

        do {
            async let msgs = SupabaseManager.shared.fetchCurationMessages(curationId: id)
            async let items = SupabaseManager.shared.fetchCurationItems(curationId: id)
            messages = try await msgs
            curationItems = try await items
            rebuildMessageItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Rebuilds messageItems mapping by matching item created_at to assistant message windows
    private func rebuildMessageItems() {
        messageItems = [:]
        let assistantMessages = messages.filter { $0.role == "assistant" }
        guard !assistantMessages.isEmpty else { return }

        for (index, msg) in assistantMessages.enumerated() {
            guard let msgDate = msg.createdAt else { continue }
            let nextDate = (index + 1 < assistantMessages.count)
                ? assistantMessages[index + 1].createdAt ?? .distantFuture
                : Date.distantFuture

            let items = curationItems.filter { item in
                guard let itemDate = item.createdAt else { return false }
                return itemDate >= msgDate && itemDate < nextDate
            }
            if !items.isEmpty {
                messageItems[msg.id] = items
            }
        }
    }

    // MARK: - Load Curation Items

    func loadCurationItems() async {
        guard let curationId = activeCurationId else { return }
        do {
            curationItems = try await SupabaseManager.shared.fetchCurationItems(curationId: curationId)
        } catch {
            print("[CuratorViewModel] Failed to load items: \(error)")
        }
    }

    // MARK: - New Conversation

    func startNewConversation() {
        messages = []
        curationItems = []
        activeCurationId = nil
        selectedItemIds = []
        messageItems = [:]
        activities = []
        researchPlan = nil
        error = nil
    }

    // MARK: - Selection

    func toggleSelection(_ id: UUID) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
        } else {
            selectedItemIds.insert(id)
        }
    }

    func selectAll() {
        selectedItemIds = Set(curationItems.map(\.id))
    }

    func deselectAll() {
        selectedItemIds.removeAll()
    }

    // MARK: - Past Curations

    func loadPastCurations() async {
        do {
            pastCurations = try await SupabaseManager.shared.fetchPastCurations(userId: userId)
        } catch {
            print("[CuratorViewModel] Failed to load past curations: \(error)")
        }
    }

    // MARK: - Save to Library

    func saveSelectedToLibrary(appState: AppState) async {
        let selected = curationItems.filter { selectedItemIds.contains($0.id) }
        let _ = appState.addCuratedItems(selected)

        // Mark items as saved in Supabase and post bookmark interactions
        for item in selected {
            try? await SupabaseManager.shared.markCurationItemSaved(itemId: item.id)
            if let contentId = item.contentId {
                try? await SupabaseManager.shared.postInteraction(
                    userId: userId,
                    contentId: contentId,
                    kind: "bookmark"
                )
            }
        }

        selectedItemIds.removeAll()
    }
}
