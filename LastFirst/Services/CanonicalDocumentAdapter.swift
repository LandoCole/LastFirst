import Foundation

struct CanonicalDocumentAdapter {
    static func buildReaderDocument(
        from packages: CanonicalDocumentPackages,
        source: DocumentSource,
        ingestionVersion: Int
    ) -> ReaderDocument {
        let manifest = packages.manifest
        let metadata = DocumentMetadata(
            title: manifest.title.isEmpty ? "Untitled" : manifest.title,
            author: manifest.authors.first,
            languageCode: manifest.languageCode
        )

        let units = packages.textAnchorsPackage.units.sorted { $0.order < $1.order }
        let segmentsByUnit = Dictionary(grouping: packages.textAnchorsPackage.segments, by: \.unitID)

        var tokens: [Token] = []
        tokens.reserveCapacity(packages.textAnchorsPackage.plainText.count / 4)

        var chapters: [Chapter] = []
        var toc: [TOCEntry] = []
        var blocks: [TextBlock] = []

        var wordIndex = 0
        var sentenceIndex = 0

        for unit in units {
            let unitTitle = unit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !unitTitle.isEmpty {
                tokens.append(Token(
                    id: tokens.count,
                    text: unitTitle,
                    kind: .chapterTitle,
                    blockIndex: 0,
                    sentenceIndex: sentenceIndex,
                    sourceLocation: documentLocation(for: source, unit: unit)
                ))
            }

            let startWordIndex = wordIndex
            let segments = (segmentsByUnit[unit.id] ?? []).sorted { $0.order < $1.order }

            for (segmentIndex, segment) in segments.enumerated() {
                let blockKind = mapBlockKind(segment.structuralKind)
                let blockStartTokenIndex = tokens.count

                // Emit list bullet prefix for list items
                if segment.structuralKind == .listItem {
                    tokens.append(Token(
                        id: tokens.count,
                        text: "•",
                        kind: .listBullet,
                        blockIndex: 0,
                        sentenceIndex: sentenceIndex,
                        sourceLocation: documentLocation(for: source, unit: unit)
                    ))
                }

                // Emit image alt text
                if segment.structuralKind == .image {
                    let altText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !altText.isEmpty {
                        tokens.append(Token(
                            id: tokens.count,
                            text: altText,
                            kind: .imageAlt,
                            blockIndex: 0,
                            sentenceIndex: sentenceIndex,
                            sourceLocation: documentLocation(for: source, unit: unit)
                        ))
                    }
                    // Create block for image
                    let blockEndTokenIndex = tokens.count
                    if blockEndTokenIndex > blockStartTokenIndex {
                        blocks.append(TextBlock(
                            sectionIndex: 0,
                            kind: .paragraph,
                            rawText: altText,
                            tokenRange: blockStartTokenIndex..<blockEndTokenIndex,
                            sourceLocation: documentLocation(for: source, unit: unit)
                        ))
                    }
                    continue
                }

                // Dividers produce a paragraph break
                if segment.structuralKind == .divider {
                    if wordIndex > 0 {
                        tokens.append(Token(
                            id: tokens.count,
                            text: "",
                            kind: .paragraphBreak,
                            blockIndex: 0,
                            sentenceIndex: sentenceIndex,
                            sourceLocation: nil
                        ))
                    }
                    continue
                }

                let words = segment.text
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                    .filter { !$0.isEmpty }

                for word in words {
                    // Check if this word contains a footnote reference marker
                    let tokenKind: TokenKind = .word

                    tokens.append(Token(
                        id: tokens.count,
                        text: word,
                        kind: tokenKind,
                        blockIndex: 0,
                        sentenceIndex: sentenceIndex,
                        sourceLocation: documentLocation(for: source, unit: unit)
                    ))
                    wordIndex += 1

                    if word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?") {
                        sentenceIndex += 1
                    }
                }

                // Create a block for this structural segment (not fixed 200-token chunks)
                let blockEndTokenIndex = tokens.count
                if blockEndTokenIndex > blockStartTokenIndex {
                    // Safety valve: split very long segments into blocks of max 200 tokens
                    let segmentTokenCount = blockEndTokenIndex - blockStartTokenIndex
                    if segmentTokenCount > 200 {
                        var chunkStart = blockStartTokenIndex
                        while chunkStart < blockEndTokenIndex {
                            let chunkEnd = min(chunkStart + 200, blockEndTokenIndex)
                            let rawText = tokens[chunkStart..<chunkEnd].map(\.text).joined(separator: " ")
                            blocks.append(TextBlock(
                                sectionIndex: 0,
                                kind: blockKind,
                                rawText: rawText,
                                tokenRange: chunkStart..<chunkEnd,
                                sourceLocation: documentLocation(for: source, unit: unit)
                            ))
                            chunkStart = chunkEnd
                        }
                    } else {
                        let rawText = tokens[blockStartTokenIndex..<blockEndTokenIndex].map(\.text).joined(separator: " ")
                        blocks.append(TextBlock(
                            sectionIndex: 0,
                            kind: blockKind,
                            rawText: rawText,
                            tokenRange: blockStartTokenIndex..<blockEndTokenIndex,
                            sourceLocation: documentLocation(for: source, unit: unit)
                        ))
                    }
                }

                // Paragraph break between segments
                if segmentIndex < segments.count - 1, wordIndex > startWordIndex {
                    tokens.append(Token(
                        id: tokens.count,
                        text: "",
                        kind: .paragraphBreak,
                        blockIndex: 0,
                        sentenceIndex: sentenceIndex,
                        sourceLocation: nil
                    ))
                }
            }

            if wordIndex > startWordIndex {
                let chapterTitle = unitTitle.isEmpty ? "Section \(unit.order + 1)" : unitTitle
                let chapter = Chapter(
                    title: chapterTitle,
                    startWordIndex: startWordIndex,
                    endWordIndex: max(startWordIndex, wordIndex - 1)
                )
                chapters.append(chapter)
                if let location = documentLocation(for: source, unit: unit) {
                    toc.append(TOCEntry(title: chapterTitle, location: location))
                }
            }
        }

        // If no structural segments produced blocks, fall back to chunking
        if blocks.isEmpty && !tokens.isEmpty {
            blocks = buildFallbackBlocks(from: tokens)
        }

        // Assign block indices to tokens
        var fixedTokens = tokens
        for blockIndex in 0..<blocks.count {
            let range = blocks[blockIndex].tokenRange
            for tokenIndex in range {
                if tokenIndex < fixedTokens.count {
                    fixedTokens[tokenIndex].blockIndex = blockIndex
                }
            }
        }

        let sections = buildSections(from: chapters, tokens: fixedTokens, blocks: blocks)

        return ReaderDocument(
            id: manifest.id,
            source: source,
            metadata: metadata,
            toc: toc,
            chapters: chapters,
            sections: sections,
            blocks: blocks,
            tokens: fixedTokens,
            resources: [],
            buildInfo: BuildInfo(ingestionVersion: ingestionVersion)
        )
    }

    // MARK: - Helpers

    private static func mapBlockKind(_ structuralKind: StructuralContentKind?) -> BlockKind {
        guard let kind = structuralKind else { return .paragraph }
        switch kind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return .heading
        case .paragraph:
            return .paragraph
        case .listItem:
            return .listItem
        case .blockquote:
            return .quote
        case .codeBlock:
            return .code
        case .image, .divider:
            return .paragraph
        }
    }

    private static func documentLocation(for source: DocumentSource, unit: ReadingUnit) -> DocumentLocation? {
        switch source {
        case .localFile(let local):
            switch local.fileType {
            case .epub:
                return .epub(.init(spineHref: unit.id, progression: nil, cfi: nil))
            case .pdf:
                return .pdf(.init(fileURL: local.url, pageIndex: unit.order, rect: nil))
            }
        case .web(let web):
            return .web(.init(url: web.url, domPath: nil, textOffset: nil))
        }
    }

    private static func buildFallbackBlocks(from tokens: [Token], blockSize: Int = 200) -> [TextBlock] {
        guard !tokens.isEmpty else { return [] }
        return stride(from: 0, to: tokens.count, by: blockSize).map { start in
            let end = min(start + blockSize, tokens.count)
            let rawText = tokens[start..<end].map(\.text).joined(separator: " ")
            return TextBlock(
                sectionIndex: 0,
                kind: .paragraph,
                rawText: rawText,
                tokenRange: start..<end,
                sourceLocation: nil
            )
        }
    }

    private static func buildSections(from chapters: [Chapter], tokens: [Token], blocks: [TextBlock]) -> [ReaderSection] {
        guard !chapters.isEmpty, !blocks.isEmpty else {
            return blocks.isEmpty ? [] : [ReaderSection(title: "Content", blockRange: 0..<blocks.count)]
        }

        var sections: [ReaderSection] = []
        for chapter in chapters {
            let start = max(0, min(chapter.startWordIndex, tokens.count))
            let endExclusive = max(start, min(chapter.endWordIndex + 1, tokens.count))

            let startBlock = blocks.firstIndex(where: { $0.tokenRange.contains(start) }) ?? 0
            let endBlock = blocks.lastIndex(where: { $0.tokenRange.overlaps(start..<endExclusive) }) ?? startBlock

            sections.append(ReaderSection(title: chapter.title, blockRange: startBlock..<(endBlock + 1)))
        }

        return sections
    }
}
