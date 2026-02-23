import SwiftUI

struct SignupInterestsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selected: Set<String> = []

    private let primaryColor = Color(hex: 0x463F3A)
    private let bgColor = Color(hex: 0xF4F3EE)
    private let secondaryColor = Color(hex: 0x8A817C)

    private let categories = [
        "Politics & Policy",
        "World News",
        "Business & Economy",
        "Technology",
        "Science & Climate",
        "Arts & Culture",
        "Opinion & Editorial",
        "Food & Cooking",
        "Health & Wellness",
        "Sports",
        "Real Estate",
        "Travel",
        "Style & Fashion",
        "Classic Literature",
        "History",
        "Self Help",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 48)

                    // Title
                    Text("What Interests you?")
                        .font(.hedvigLettersSerif(24))
                        .foregroundStyle(primaryColor)

                    // Vertical list of interests
                    VStack(spacing: 0) {
                        ForEach(categories, id: \.self) { category in
                            let isSelected = selected.contains(category)
                            Button {
                                if isSelected {
                                    selected.remove(category)
                                } else {
                                    selected.insert(category)
                                }
                            } label: {
                                HStack {
                                    Text("\(isSelected ? "-" : "+")  \(category)")
                                        .font(.rethinkSans(20))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(isSelected ? primaryColor : Color.clear)
                                .foregroundStyle(isSelected ? .white : primaryColor)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Bottom pinned section
            VStack(spacing: 12) {
                // Done button
                Button {
                    Task { await handleDone() }
                } label: {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Done")
                                .font(.rethinkSans(16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(authViewModel.isLoading)

                // Skip
                Button {
                    finishFlow()
                } label: {
                    Text("Skip \u{2192}")
                        .font(.rethinkSans(14))
                        .foregroundStyle(primaryColor)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(bgColor)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func handleDone() async {
        if !selected.isEmpty {
            await authViewModel.saveInterests(Array(selected))
        }
        finishFlow()
    }

    private func finishFlow() {
        authViewModel.needsOnboarding = false
        authViewModel.authFlowPath = []
    }
}
