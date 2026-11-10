import AppKit
import Foundation
import PDFKit

enum IngestionError: LocalizedError {
    case unsupported, empty
    var errorDescription: String? { self == .empty ? "No readable text was found." : "This file type is not supported yet." }
}

nonisolated enum DocumentIngestion {
    static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let text: String
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw IngestionError.unsupported }
            text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n\n")
        } else if ["docx", "rtf", "rtfd", "doc"].contains(ext) {
            let data = try Data(contentsOf: url)
            text = try NSAttributedString(data: data, options: [:], documentAttributes: nil).string
        } else if ["txt", "md", "csv", "tsv"].contains(ext) {
            text = try String(contentsOf: url, encoding: .utf8)
        } else { throw IngestionError.unsupported }
        let cleaned = text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw IngestionError.empty }
        return cleaned
    }
}

nonisolated enum CitationExtractor {
    static func extract(from text: String) -> [String] {
        let patterns = [#"\([A-Z][A-Za-z'’-]+(?:\s+(?:et al\.|&\s*[A-Z][A-Za-z'’-]+))?,\s*(?:19|20)\d{2}[a-z]?\)"#,
                        #"\b10\.\d{4,9}/[-._;()/:A-Z0-9]+\b"#]
        var found = Set<String>()
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in re.matches(in: text, range: range) where match.range.location != NSNotFound {
                if let r = Range(match.range, in: text) { found.insert(String(text[r])) }
            }
        }
        return found.sorted()
    }
}

private struct CrossrefResponse: Decodable {
    struct Message: Decodable { let items: [Item] }
    struct Item: Decodable {
        struct DateParts: Decodable { let dateParts: [[Int]]; enum CodingKeys: String, CodingKey { case dateParts = "date-parts" } }
        struct Author: Decodable { let given: String?; let family: String? }
        let DOI: String?; let URL: String?; let title: [String]?; let author: [Author]?; let published: DateParts?; let containerTitle: [String]?
        enum CodingKeys: String, CodingKey { case DOI, URL, title, author, published; case containerTitle = "container-title" }
    }
    let message: Message
}

nonisolated enum CrossrefService {
    static func search(query: String) async throws -> [LiteratureResult] {
        var parts = URLComponents(string: "https://api.crossref.org/works")!
        parts.queryItems = [.init(name: "query.bibliographic", value: query), .init(name: "rows", value: "20"), .init(name: "select", value: "DOI,title,author,published,container-title,URL")]
        var request = URLRequest(url: parts.url!); request.setValue("ScholarForge/0.1 (academic research workspace)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(CrossrefResponse.self, from: data)
        return decoded.message.items.map { item in
            let authors = item.author?.prefix(4).map { [$0.family, $0.given].compactMap{$0}.joined(separator: ", ") }.joined(separator: "; ") ?? "Unknown author"
            let year = item.published?.dateParts.first?.first.map(String.init) ?? "n.d."
            return LiteratureResult(id: item.DOI ?? item.URL ?? UUID().uuidString, title: item.title?.first ?? "Untitled", authors: authors, year: year, venue: item.containerTitle?.first ?? "", doi: item.DOI ?? "", url: item.URL ?? "")
        }
    }
}

nonisolated enum ChapterExporter {
    static func write(manuscript: ManuscriptProject, to url: URL) throws {
        let heading = "\(manuscript.title)\n\n\(manuscript.author)\n\(manuscript.degree)"
        let chapters = manuscript.chapters.map { "\($0.title)\n\n\($0.content)" }.joined(separator: "\n\n")
        let attributed = NSMutableAttributedString(string: "\(heading)\n\n\(chapters)", attributes: [.font: NSFont(name: "Times New Roman", size: 12) ?? .systemFont(ofSize: 12), .foregroundColor: NSColor.textColor])
        let full = NSRange(location: 0, length: attributed.length)
        let style = NSMutableParagraphStyle(); style.lineSpacing = 6; style.paragraphSpacing = 8
        attributed.addAttribute(.paragraphStyle, value: style, range: full)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        let data = try attributed.data(from: full, documentAttributes: attributes)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    static func write(project: ThesisProject, to url: URL) throws {
        let requirements = project.requirements.map { "\($0.met ? "✓" : "○") \($0.text)" }.joined(separator: "\n")
        let evidence = project.evidence.map { "\($0.citation)\n\($0.finding)\nUse: \($0.use)\n" }.joined(separator: "\n")
        let body = "Chapter 5 Discussion Conclusions and Recommendations\n\nProject\n\(project.title)\n\nResearch question\n\(project.researchQuestion)\n\nSupervisor requirements\n\(requirements)\n\nArgument workspace\n\(project.chapterDraft)\n\nEvidence ledger\n\(evidence)"
        let attributed = NSAttributedString(string: body, attributes: [.font: NSFont(name: "Arial", size: 11) ?? .systemFont(ofSize: 11), .foregroundColor: NSColor.textColor])
        let range = NSRange(location: 0, length: attributed.length)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        let data = try attributed.data(from: range, documentAttributes: attributes)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }
}
