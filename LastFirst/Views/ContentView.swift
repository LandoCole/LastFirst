import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLibrary: Bool = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if let book = appState.currentBook {
                ReadingView(book: book)
            } else {
                welcomeView
            }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                // Icon representation
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 32, height: 32)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary)
                        .frame(width: 8, height: 48)
                }

                Text("Last First")
                    .font(.system(size: 36, weight: .bold, design: .default))
                    .foregroundColor(.primary)
            }

            Text("Speed Reading, Reimagined")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            // Quick start
            VStack(spacing: 16) {
                if !appState.library.isEmpty {
                    // Continue reading button
                    if let lastBook = appState.library.first {
                        Button(action: { appState.currentBook = lastBook }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue Reading")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(lastBook.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Open library button
                Button(action: { showLibrary = true }) {
                    HStack {
                        Image(systemName: "books.vertical")
                        Text(appState.library.isEmpty ? "Import Your First Book" : "Open Library")
                    }
                    .font(.headline)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Footer
            VStack(spacing: 8) {
                Text("Supports ePub, PDF, and text files")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 32)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
