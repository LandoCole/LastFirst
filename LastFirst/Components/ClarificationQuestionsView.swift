import SwiftUI

struct ClarificationQuestionsView: View {
    let questions: [ClarificationQuestion]
    @Binding var selections: [String: Set<String>]
    let onSubmit: () -> Void
    let canSubmit: Bool

    private let gold = Color(hex: "B08D57")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(question.question)
                            .font(.rethinkSans(13, weight: .medium))
                        if question.isMultiSelect {
                            Text("(select multiple)")
                                .font(.rethinkSans(11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(question.options) { option in
                            let isSelected = selections[question.id]?.contains(option.id) ?? false
                            optionChip(option: option, isSelected: isSelected) {
                                toggleOption(questionId: question.id, optionId: option.id, question: question)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: onSubmit) {
                    HStack(spacing: 6) {
                        Text("Continue")
                            .font(.rethinkSans(14, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(canSubmit ? gold : Color.secondary.opacity(0.3))
                    .clipShape(Capsule())
                }
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func optionChip(option: ClarificationOption, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let emoji = option.emoji {
                    Text(emoji)
                        .font(.system(size: 14))
                }
                Text(option.label)
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

    private func toggleOption(questionId: String, optionId: String, question: ClarificationQuestion) {
        var selected = selections[questionId] ?? []
        if question.isMultiSelect {
            if selected.contains(optionId) {
                selected.remove(optionId)
            } else {
                selected.insert(optionId)
            }
        } else {
            selected = [optionId]
        }
        withAnimation(.easeOut(duration: 0.2)) {
            selections[questionId] = selected
        }
    }
}
