import Foundation

/// Extracts metadata from EPUB OPF and navigation documents that EPUBKit doesn't expose:
/// page-list, landmarks, rendition properties, book version, specified-fonts flag.
struct EPUBMetadataExtractor {

    struct ExtractedMetadata: Sendable {
        var pageList: [PageListEntry]
        var landmarks: [LandmarkEntry]
        var renditionLayout: RenditionLayout?
        var renditionFlow: RenditionFlow?
        var renditionSpread: RenditionSpread?
        var bookVersion: String?
        var specifiedFonts: Bool
    }

    struct LandmarkEntry: Codable, Sendable {
        var type: String
        var title: String
        var href: String
    }

    enum RenditionLayout: String, Codable, Sendable {
        case reflowable
        case prePageinated = "pre-paginated"
    }

    enum RenditionFlow: String, Codable, Sendable {
        case paginated
        case scrolledContinuous = "scrolled-continuous"
        case scrolledDoc = "scrolled-doc"
        case auto
    }

    enum RenditionSpread: String, Codable, Sendable {
        case auto
        case landscape
        case both
        case none
    }

    // MARK: - Public API

    /// Extract metadata from an OPF file.
    func extractFromOPF(at url: URL) -> ExtractedMetadata {
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }
        let parser = OPFParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.parse()
        return parser.result
    }

    /// Extract page-list and landmarks from an EPUB navigation document (nav.xhtml).
    func extractFromNavDocument(at url: URL) -> (pageList: [PageListEntry], landmarks: [LandmarkEntry]) {
        guard let data = try? Data(contentsOf: url) else {
            return ([], [])
        }
        let parser = NavParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.parse()
        return (parser.pageList, parser.landmarks)
    }
}

extension EPUBMetadataExtractor.ExtractedMetadata {
    static let empty = EPUBMetadataExtractor.ExtractedMetadata(
        pageList: [],
        landmarks: [],
        renditionLayout: nil,
        renditionFlow: nil,
        renditionSpread: nil,
        bookVersion: nil,
        specifiedFonts: false
    )
}

// MARK: - OPF Parser

private class OPFParser: NSObject, XMLParserDelegate {
    var result = EPUBMetadataExtractor.ExtractedMetadata.empty

    private var currentElement: String = ""
    private var currentText: String = ""
    private var currentAttributes: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""
        currentAttributes = attributeDict
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if tag == "meta" {
            let property = currentAttributes["property"]?.lowercased() ?? ""
            let name = currentAttributes["name"]?.lowercased() ?? ""
            let content = currentAttributes["content"] ?? text

            switch property {
            case "rendition:layout":
                result.renditionLayout = EPUBMetadataExtractor.RenditionLayout(rawValue: content)
            case "rendition:flow":
                result.renditionFlow = EPUBMetadataExtractor.RenditionFlow(rawValue: content)
            case "rendition:spread":
                result.renditionSpread = EPUBMetadataExtractor.RenditionSpread(rawValue: content)
            case "ibooks:version":
                result.bookVersion = content
            case "ibooks:specified-fonts":
                result.specifiedFonts = content.lowercased() == "true"
            default:
                break
            }

            if name == "ibooks:specified-fonts" {
                result.specifiedFonts = content.lowercased() == "true"
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Silently ignore
    }
}

// MARK: - Navigation Document Parser

private class NavParser: NSObject, XMLParserDelegate {
    var pageList: [PageListEntry] = []
    var landmarks: [EPUBMetadataExtractor.LandmarkEntry] = []

    private var elementStack: [String] = []
    private var inPageList = false
    private var inLandmarks = false
    private var currentText = ""
    private var currentHref: String?
    private var currentEpubType: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.lowercased()
        elementStack.append(tag)

        if tag == "nav" {
            let epubType = attributeDict["epub:type"] ?? attributeDict["epub\\:type"] ?? ""
            if epubType.contains("page-list") {
                inPageList = true
                inLandmarks = false
            } else if epubType.contains("landmarks") {
                inLandmarks = true
                inPageList = false
            }
        }

        if tag == "a" {
            currentHref = attributeDict["href"]
            currentEpubType = attributeDict["epub:type"] ?? attributeDict["epub\\:type"]
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = elementName.lowercased()

        if tag == "a" {
            let label = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            let href = currentHref ?? ""

            if inPageList && !label.isEmpty {
                let components = href.split(separator: "#", maxSplits: 1)
                let unitRef = components.first.map(String.init) ?? href
                let anchor = components.count > 1 ? String(components[1]) : nil
                pageList.append(PageListEntry(
                    label: label,
                    unitID: unitRef,
                    anchorID: anchor
                ))
            }

            if inLandmarks && !label.isEmpty {
                landmarks.append(EPUBMetadataExtractor.LandmarkEntry(
                    type: currentEpubType ?? "",
                    title: label,
                    href: href
                ))
            }

            currentHref = nil
            currentEpubType = nil
            currentText = ""
        }

        if tag == "nav" {
            inPageList = false
            inLandmarks = false
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Silently ignore
    }
}
