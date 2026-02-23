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

    private let quotes = [
        "An expert in anything was once a beginner\n—Helen Hayes",
        "A reader lives a thousand lives before he dies\n—George R.R. Martin",
        "The more that you read, the more things you will know\n—Dr. Seuss",
        "Reading is to the mind what exercise is to the body\n—Joseph Addison"
    ]

    init(inputText: Binding<String>) {
        self._inputText = inputText
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 34)

            Spacer()

            quoteView

            Spacer()

            inputBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                // Future: show chat history
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
                // Future: send message
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(inputText.isEmpty)
        }
    }
}
