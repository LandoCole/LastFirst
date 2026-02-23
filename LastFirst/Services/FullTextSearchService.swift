import Foundation

/// Searches through token-based text content for all reading modes.
/// For scan mode, search delegates to the JS bridge instead.
struct FullTextSearchService {

    /// Search for a query string in the document's words and return results with context.
    static func search(
        query: String,
        words: [String],
        chapters: [Chapter],
        maxResults: Int = 100
    ) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2 else { return [] }

        var results: [SearchResult] = []
        let queryWords = trimmed.split(separator: " ").map(String.init)

        for (wordIndex, word) in words.enumerated() {
            guard results.count < maxResults else { break }

            let lowerWord = word.lowercased()

            // Single-word match
            if queryWords.count == 1 {
                if lowerWord.contains(trimmed) {
                    let excerpt = buildExcerpt(around: wordIndex, words: words)
                    let chapterTitle = findChapter(for: wordIndex, chapters: chapters)
                    results.append(SearchResult(
                        wordIndex: wordIndex,
                        tokenIndex: wordIndex,
                        excerpt: excerpt,
                        chapterTitle: chapterTitle
                    ))
                }
            } else {
                // Multi-word phrase match
                if lowerWord.hasPrefix(queryWords[0]) || lowerWord.contains(queryWords[0]) {
                    let phraseMatches = matchPhrase(queryWords: queryWords, startingAt: wordIndex, words: words)
                    if phraseMatches {
                        let excerpt = buildExcerpt(around: wordIndex, words: words)
                        let chapterTitle = findChapter(for: wordIndex, chapters: chapters)
                        results.append(SearchResult(
                            wordIndex: wordIndex,
                            tokenIndex: wordIndex,
                            excerpt: excerpt,
                            chapterTitle: chapterTitle
                        ))
                    }
                }
            }
        }

        return results
    }

    // MARK: - Helpers

    private static func matchPhrase(queryWords: [String], startingAt index: Int, words: [String]) -> Bool {
        for (offset, queryWord) in queryWords.enumerated() {
            let targetIndex = index + offset
            guard targetIndex < words.count else { return false }
            if !words[targetIndex].lowercased().contains(queryWord) {
                return false
            }
        }
        return true
    }

    private static func buildExcerpt(around index: Int, words: [String], contextWords: Int = 8) -> String {
        let start = max(0, index - contextWords)
        let end = min(words.count, index + contextWords + 1)
        var excerpt = words[start..<end].joined(separator: " ")

        if start > 0 {
            excerpt = "…" + excerpt
        }
        if end < words.count {
            excerpt += "…"
        }

        return excerpt
    }

    private static func findChapter(for wordIndex: Int, chapters: [Chapter]) -> String? {
        chapters.last(where: { $0.startWordIndex <= wordIndex })?.title
    }
}
