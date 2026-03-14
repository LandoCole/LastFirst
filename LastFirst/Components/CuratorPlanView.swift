import SwiftUI

struct CuratorPlanView: View {
    let plan: CuratorResearchPlan

    private let gold = Color(hex: "B08D57")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(gold)
                Text("Research Plan")
                    .font(.rethinkSans(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            // Steps
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    // Left rail: icon + connecting line
                    VStack(spacing: 0) {
                        stepIcon(for: step.state)
                            .frame(width: 18, height: 18)

                        if index < plan.steps.count - 1 {
                            Rectangle()
                                .fill(lineColor(for: step.state))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }

                    // Step content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.label)
                            .font(.rethinkSans(13, weight: .medium))
                            .foregroundStyle(step.state == .pending ? .tertiary : .primary)

                        Text(step.description)
                            .font(.rethinkSans(11))
                            .foregroundStyle(.tertiary)

                        // Finding card
                        if let finding = step.finding, step.state == .complete {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(gold)
                                    .padding(.top, 2)

                                Text(finding)
                                    .font(.rethinkSans(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(gold.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            // Agent progress section
            if !plan.agents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(gold)
                        Text("Research Agents")
                            .font(.rethinkSans(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                    ForEach(plan.agents) { agent in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                stepIcon(for: agent.state)
                                    .frame(width: 18, height: 18)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(agentRoleDisplayName(agent.role))
                                    .font(.rethinkSans(13, weight: .medium))
                                    .foregroundStyle(agent.state == .pending ? .tertiary : .primary)

                                if let finding = agent.finding, agent.state == .complete {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(gold)
                                            .padding(.top, 2)

                                        Text(finding)
                                            .font(.rethinkSans(11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(gold.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.3), value: plan)
    }

    private func agentRoleDisplayName(_ role: String) -> String {
        switch role {
        case "preference_analyst": return "Preference Analyst"
        case "library_searcher": return "Library Searcher"
        case "web_researcher": return "Web Researcher"
        default: return role.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @ViewBuilder
    private func stepIcon(for state: CuratorStepState) -> some View {
        switch state {
        case .pending:
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                .frame(width: 14, height: 14)
        case .active:
            Circle()
                .fill(gold)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(gold.opacity(0.3), lineWidth: 3)
                        .scaleEffect(1.4)
                )
                .modifier(PulseModifier())
        case .complete:
            ZStack {
                Circle()
                    .fill(gold)
                    .frame(width: 14, height: 14)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func lineColor(for state: CuratorStepState) -> Color {
        switch state {
        case .complete: return gold.opacity(0.5)
        case .active: return gold.opacity(0.3)
        case .pending: return Color.secondary.opacity(0.15)
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
