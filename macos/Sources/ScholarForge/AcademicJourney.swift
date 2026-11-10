import Foundation
import CryptoKit

struct JourneyLink: Codable, Identifiable, Equatable {
    var id: String
    var chapterIndex: Int
    var chapterTitle: String
    var concept: String
    var passage: String
    var evidence = ""
    var decision = ""
    var limitation = ""
    var reviewNotes = ""
    var priority = false
    var evidenceStatus: String?
    var sourceIDs: [String]?
    var evidenceReviewPending: Bool { evidenceStatus != "reviewed_scope" && evidenceStatus != "author_design" && evidenceStatus != "reviewed_interpretation" && evidenceStatus != "reviewed_record" }
    var evidenceLabel: String {
        switch evidenceStatus {
        case "reviewed_scope": "Reviewed source scope"
        case "reviewed_interpretation": "Scoped interpretation reviewed; no new measured effect"
        case "reviewed_record": "Local record inspected; bounded test evidence"
        case "source_linked": "Source linked; passage review pending"
        case "author_design": "Author design or interpretation, not a measured result"
        case "internal_record": "Internal record linked; review its scope"
        default: "Evidence review pending"
        }
    }
    var missingCount: Int { [evidence, decision, limitation].filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var searchText: String { [concept, chapterTitle, passage, evidence, decision, limitation, reviewNotes].joined(separator: " ") }
}

struct JourneyEdition: Identifiable {
    var id: String { path }
    var title: String
    var path: String
}

enum AcademicJourney {
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// A literal passage index, not inferred evidence or automatic scholarly approval.
    static func extract(projectID: String, chapters: [ManuscriptChapter]) -> [JourneyLink] {
        var links: [JourneyLink] = []
        for (index, chapter) in chapters.enumerated() where !["references", "bibliography", "rujukan"].contains(where: { chapter.title.localizedCaseInsensitiveContains($0) }) {
            var heading = chapter.title
            var needsPassage = true
            for raw in chapter.content.components(separatedBy: "\n\n") {
                let block = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if block.hasPrefix("#") || (block.count < 200 && !block.contains("\n") && block.range(of: #"^\d+\.\d+(?:\.\d+)*\s"#, options: .regularExpression) != nil) {
                    heading = block.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    needsPassage = true
                } else if needsPassage && block.count > 100 && !block.hasPrefix("|") && !block.hasPrefix("![") {
                    links.append(JourneyLink(id: digest("\(projectID)|\(index)|\(heading)|\(block)"), chapterIndex: index, chapterTitle: chapter.title, concept: heading, passage: block))
                    needsPassage = false
                }
            }
        }
        return links
    }

    static func reconcile(projectID: String, chapters: [ManuscriptChapter], saved: [JourneyLink]) -> (current: [JourneyLink], archived: [JourneyLink]) {
        let fresh = extract(projectID: projectID, chapters: chapters)
        let current = fresh.map { item in
            saved.first(where: { $0.id == item.id && $0.passage == item.passage && $0.concept == item.concept }) ?? item
        }
        let ids = Set(current.map(\.id))
        return (current, saved.filter { !ids.contains($0.id) })
    }

    static func isCurrent(_ link: JourneyLink, chapters: [ManuscriptChapter]) -> Bool {
        chapters.indices.contains(link.chapterIndex) && chapters[link.chapterIndex].content.contains(link.passage)
    }

    static func markdown(_ links: [JourneyLink]) -> String {
        "# Evidence to decision journey\n\nWorking notes, not verification or submission approval.\n\n" + links.map {
            "## \($0.concept)\n\nLocation: \($0.chapterTitle)\n\n### Thesis passage\n\n\($0.passage)\n\n### Evidence and locator\n\n\($0.evidence.isEmpty ? "Not linked" : $0.evidence)\n\n### Decision\n\n\($0.decision.isEmpty ? "Not recorded" : $0.decision)\n\n### Limitation\n\n\($0.limitation.isEmpty ? "Not recorded" : $0.limitation)\n\n### Review notes\n\n\($0.reviewNotes)"
        }.joined(separator: "\n\n")
    }
}

enum SectionPreservingEdit {
    struct UnsafeStructure: LocalizedError {
        var errorDescription: String? { "The section headings changed or became ambiguous. Your edit is retained locally. Restore the original section headings before saving to the shared manuscript; no structured sections were overwritten." }
    }
    static func apply(_ text: String, to sections: [String: [String: Any]]) throws -> [String: [String: Any]] {
        let keys = orderedKeys(sections)
        if keys.isEmpty { throw UnsafeStructure() }
        var result = sections
        var pieces: [String] = []
        if keys.count == 1 { pieces = [text] }
        else {
            var start = text.startIndex
            for key in keys.dropFirst() {
                guard let original = sections[key]?["content"] as? String,
                      let first = original.split(separator: "\n", omittingEmptySubsequences: true).first else { throw UnsafeStructure() }
                let marker = "\n\n" + String(first) + "\n"
                guard let range = text.range(of: marker, range: start..<text.endIndex),
                      text.range(of: marker, range: range.upperBound..<text.endIndex) == nil else { throw UnsafeStructure() }
                pieces.append(String(text[start..<range.lowerBound]))
                start = text.index(range.lowerBound, offsetBy: 2)
            }
            pieces.append(String(text[start...]))
        }
        for (key, piece) in zip(keys, pieces) {
            if piece != sections[key]?["content"] as? String {
                result[key]?["content"] = piece
                result[key]?["status"] = "draft"
                result[key]?["word_count"] = ManuscriptChapter.countWords(piece)
                result[key]?["updated_at"] = ISO8601DateFormatter().string(from: .now)
            }
        }
        return result
    }
    static func orderedKeys(_ sections: [String: [String: Any]]) -> [String] {
        sections.keys.sorted {
            func rank(_ key: String) -> Int { key == "Mac application draft" ? 0 : key == "Recovered working draft" ? 1 : 2 }
            return rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1)
        }
    }
}
