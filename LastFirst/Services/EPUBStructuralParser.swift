import Foundation

struct StructuralElement: Sendable {
    enum Kind: Sendable {
        case heading(level: Int)
        case paragraph
        case listItem(ordinal: Int?)
        case blockquote
        case codeBlock
        case image(alt: String?, src: String?)
        case footnoteRef(targetId: String, displayText: String)
        case footnoteBody(id: String)
        case divider
    }

    let kind: Kind
    let text: String
    let htmlFragment: String
}

/// Parses EPUB XHTML spine items into structured elements using Foundation's XMLParser.
/// Walks the DOM depth-first, recognizing headings, lists, blockquotes, code blocks,
/// images, footnote references, and footnote bodies.
final class EPUBStructuralParser: NSObject, XMLParserDelegate, @unchecked Sendable {

    // MARK: - Public API

    /// Parse an XHTML file at the given URL into structural elements.
    func parse(xhtmlURL url: URL) -> [StructuralElement] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(xhtmlData: data)
    }

    /// Parse XHTML data into structural elements.
    func parse(xhtmlData data: Data) -> [StructuralElement] {
        elements = []
        elementStack = []
        textBuffer = ""
        htmlBuffer = ""
        currentListOrdinal = nil
        inFootnoteBody = false
        currentFootnoteBodyId = nil
        inPreOrCode = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.parse()

        flushCurrentElement()
        return elements
    }

    // MARK: - State

    private var elements: [StructuralElement] = []
    private var elementStack: [ElementInfo] = []
    private var textBuffer: String = ""
    private var htmlBuffer: String = ""
    private var currentListOrdinal: Int? = nil
    private var inFootnoteBody: Bool = false
    private var currentFootnoteBodyId: String? = nil
    private var inPreOrCode: Bool = false

    private struct ElementInfo {
        var tagName: String
        var attributes: [String: String]
        var epubType: String?
    }

    // MARK: - Block-level tag detection

    private static let blockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "div", "section", "article", "aside", "nav", "header", "footer",
        "blockquote", "pre", "ul", "ol", "li", "hr", "br",
        "figure", "figcaption", "table", "tr", "td", "th",
        "dl", "dt", "dd"
    ]

    private static let headingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]

    private static func headingLevel(for tag: String) -> Int? {
        switch tag {
        case "h1": return 1
        case "h2": return 2
        case "h3": return 3
        case "h4": return 4
        case "h5": return 5
        case "h6": return 6
        default: return nil
        }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.lowercased()
        let epubType = attributeDict["epub:type"] ?? attributeDict["epub\\:type"]

        let info = ElementInfo(tagName: tag, attributes: attributeDict, epubType: epubType)
        elementStack.append(info)

        // Handle img (self-closing or not)
        if tag == "img" {
            flushCurrentElement()
            let alt = attributeDict["alt"]
            let src = attributeDict["src"]
            let altText = alt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let htmlFrag = "<img alt=\"\(escapeHTML(altText))\" src=\"\(escapeHTML(src ?? ""))\" />"
            elements.append(StructuralElement(
                kind: .image(alt: alt, src: src),
                text: altText.isEmpty ? "[Image]" : altText,
                htmlFragment: htmlFrag
            ))
            return
        }

        // Handle hr
        if tag == "hr" {
            flushCurrentElement()
            elements.append(StructuralElement(kind: .divider, text: "", htmlFragment: "<hr />"))
            return
        }

        // Detect footnote references (epub:type="noteref")
        if tag == "a", let epubType, epubType.contains("noteref") {
            // We'll capture the text content in the characters callback
            // and flush as footnoteRef when the </a> closes
        }

        // Detect footnote bodies
        if let epubType, (epubType.contains("footnote") || epubType.contains("endnote")) && tag != "a" {
            flushCurrentElement()
            inFootnoteBody = true
            currentFootnoteBodyId = attributeDict["id"]
        }

        // Track pre/code blocks
        if tag == "pre" || (tag == "code" && !isInsidePre()) {
            flushCurrentElement()
            inPreOrCode = true
        }

        // Track list context
        if tag == "ol" {
            currentListOrdinal = 0
        } else if tag == "ul" {
            currentListOrdinal = nil
        }

        if tag == "li" {
            flushCurrentElement()
            if let ordinal = currentListOrdinal {
                currentListOrdinal = ordinal + 1
            }
        }

        // Flush on block-level element start
        if Self.blockTags.contains(tag) && tag != "li" && tag != "br" {
            flushCurrentElement()
        }

        if tag == "br" {
            textBuffer += "\n"
            htmlBuffer += "<br />"
        }

        // Append opening tag to HTML buffer for inline elements
        if !Self.blockTags.contains(tag) && tag != "img" && tag != "hr" && tag != "br" {
            htmlBuffer += "<\(tag)"
            for (key, value) in attributeDict {
                htmlBuffer += " \(key)=\"\(escapeHTML(value))\""
            }
            htmlBuffer += ">"
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = elementName.lowercased()

        // Handle footnote reference close
        if tag == "a", let current = elementStack.last, current.epubType?.contains("noteref") == true {
            let displayText = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetId = current.attributes["href"]?.replacingOccurrences(of: "#", with: "") ?? ""
            flushCurrentElement()
            elements.append(StructuralElement(
                kind: .footnoteRef(targetId: targetId, displayText: displayText),
                text: displayText,
                htmlFragment: "<a epub:type=\"noteref\" href=\"#\(escapeHTML(targetId))\">\(escapeHTML(displayText))</a>"
            ))
            elementStack.removeLast()
            return
        }

        // Close inline tag in HTML buffer
        if !Self.blockTags.contains(tag) && tag != "img" && tag != "hr" && tag != "br" {
            htmlBuffer += "</\(tag)>"
        }

        // Handle block-level element close
        if Self.blockTags.contains(tag) {
            if let level = Self.headingLevel(for: tag) {
                let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                let html = htmlBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    elements.append(StructuralElement(
                        kind: .heading(level: level),
                        text: text,
                        htmlFragment: "<\(tag)>\(html)</\(tag)>"
                    ))
                }
                textBuffer = ""
                htmlBuffer = ""
            } else if tag == "blockquote" {
                let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                let html = htmlBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    elements.append(StructuralElement(
                        kind: .blockquote,
                        text: text,
                        htmlFragment: "<blockquote>\(html)</blockquote>"
                    ))
                }
                textBuffer = ""
                htmlBuffer = ""
            } else if tag == "pre" || (tag == "code" && inPreOrCode) {
                let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                let html = htmlBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    elements.append(StructuralElement(
                        kind: .codeBlock,
                        text: text,
                        htmlFragment: "<pre><code>\(html)</code></pre>"
                    ))
                }
                textBuffer = ""
                htmlBuffer = ""
                inPreOrCode = false
            } else if tag == "li" {
                let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                let html = htmlBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    elements.append(StructuralElement(
                        kind: .listItem(ordinal: currentListOrdinal),
                        text: text,
                        htmlFragment: "<li>\(html)</li>"
                    ))
                }
                textBuffer = ""
                htmlBuffer = ""
            } else if tag == "p" || tag == "div" || tag == "section" {
                flushCurrentElement()
            }

            // End footnote body
            if inFootnoteBody && (tag == "aside" || tag == "div" || tag == "section") {
                if let footnoteId = currentFootnoteBodyId {
                    let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        elements.append(StructuralElement(
                            kind: .footnoteBody(id: footnoteId),
                            text: text,
                            htmlFragment: htmlBuffer
                        ))
                        textBuffer = ""
                        htmlBuffer = ""
                    }
                }
                inFootnoteBody = false
                currentFootnoteBodyId = nil
            }

            if tag == "ol" || tag == "ul" {
                currentListOrdinal = nil
            }
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
        htmlBuffer += escapeHTML(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += str
            htmlBuffer += escapeHTML(str)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Silently handle parse errors — EPUBs often have malformed XHTML
    }

    // MARK: - Helpers

    private func flushCurrentElement() {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            textBuffer = ""
            htmlBuffer = ""
            return
        }

        if inFootnoteBody {
            // Accumulate; don't flush yet
            return
        }

        let html = htmlBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: StructuralElement.Kind = inPreOrCode ? .codeBlock : .paragraph
        elements.append(StructuralElement(kind: kind, text: text, htmlFragment: "<p>\(html)</p>"))
        textBuffer = ""
        htmlBuffer = ""
    }

    private func isInsidePre() -> Bool {
        elementStack.contains { $0.tagName == "pre" }
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
