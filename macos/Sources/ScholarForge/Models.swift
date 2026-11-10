import Foundation

struct ThesisPROProjectSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let degree: String
    let targetWords: Int
    let fileURL: URL
    var draftWords: Int = 0
}

struct ManuscriptChapter: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var content: String
    var targetWords: Int
    var wordCount: Int { Self.countWords(content) }
    static func countWords(_ content: String) -> Int {
        content.components(separatedBy: "\n\n").filter {
            !($0.hasPrefix("![") && $0.contains("#page=") && $0.hasSuffix(")"))
        }.joined(separator: "\n\n").split(whereSeparator: \.isWhitespace).count
    }
    enum CodingKeys: String, CodingKey { case id, title, content, targetWords }
    init(id: UUID = UUID(), title: String, content: String, targetWords: Int) { self.id=id; self.title=title; self.content=content; self.targetWords=targetWords }
    init(from decoder: Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self); id=try c.decodeIfPresent(UUID.self,forKey:.id) ?? UUID(); title=try c.decode(String.self,forKey:.title); content=try c.decode(String.self,forKey:.content); targetWords=try c.decode(Int.self,forKey:.targetWords) }
}

struct ManuscriptProject: Codable {
    var title: String
    var degree: String
    var author: String
    var targetWords: Int
    var chapters: [ManuscriptChapter]
    var totalWords: Int { chapters.reduce(0) { $0 + $1.wordCount } }
    var draftWords: Int {
        chapters.filter { !$0.title.localizedCaseInsensitiveContains("references") && !$0.title.localizedCaseInsensitiveContains("appendix") }
            .reduce(0) { $0 + $1.wordCount }
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "Research Map"
    case library = "Source Library"
    case discovery = "Literature Discovery"
    case evidence = "Evidence Ledger"
    case hypotheses = "Hypotheses"
    case chapter = "Chapter Studio"
    case integrity = "Integrity Check"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "map"
        case .library: "tray.full"
        case .discovery: "magnifyingglass.circle"
        case .evidence: "books.vertical"
        case .hypotheses: "point.3.connected.trianglepath.dotted"
        case .chapter: "doc.text"
        case .integrity: "checkmark.shield"
        }
    }
}

enum ResearchStatus: String, Codable, CaseIterable { case ready = "Ready", review = "Needs review", blocked = "Blocked" }

struct ResearchStage: Identifiable, Codable, Hashable {
    var id = UUID(); var title: String; var detail: String; var progress: Double; var status: ResearchStatus
}

struct EvidenceItem: Identifiable, Codable, Hashable {
    var id = UUID(); var citation: String; var finding: String; var use: String; var verified: Bool
}

struct HypothesisItem: Identifiable, Codable, Hashable {
    var id = UUID(); var code: String; var statement: String; var result: String; var caution: String
}

struct RequirementItem: Identifiable, Codable, Hashable {
    var id = UUID(); var text: String; var met: Bool
}

struct SourceDocument: Identifiable, Codable, Hashable {
    var id = UUID(); var filename: String; var kind: String; var importedAt = Date(); var text: String; var citations: [String]
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

struct LiteratureResult: Identifiable, Hashable, Sendable {
    let id: String; let title: String; let authors: String; let year: String; let venue: String; let doi: String; let url: String
    var citation: String {
        let link = doi.isEmpty ? url : "https://doi.org/\(doi)"
        return "\(authors) (\(year)). \(title). \(venue). \(link)"
    }
}

struct ThesisProject: Codable {
    var title: String
    var degree: String
    var locale: String
    var researchQuestion: String
    var stages: [ResearchStage]
    var evidence: [EvidenceItem]
    var hypotheses: [HypothesisItem]
    var requirements: [RequirementItem]
    var documents: [SourceDocument]
    var chapterDraft: String

    enum CodingKeys: String, CodingKey { case title, degree, locale, researchQuestion, stages, evidence, hypotheses, requirements, documents, chapterDraft }
    init(title: String, degree: String, locale: String, researchQuestion: String, stages: [ResearchStage], evidence: [EvidenceItem], hypotheses: [HypothesisItem], requirements: [RequirementItem], documents: [SourceDocument], chapterDraft: String) {
        self.title=title; self.degree=degree; self.locale=locale; self.researchQuestion=researchQuestion; self.stages=stages; self.evidence=evidence; self.hypotheses=hypotheses; self.requirements=requirements; self.documents=documents; self.chapterDraft=chapterDraft
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title=try c.decode(String.self, forKey:.title); degree=try c.decode(String.self, forKey:.degree); locale=try c.decode(String.self, forKey:.locale); researchQuestion=try c.decode(String.self, forKey:.researchQuestion)
        stages=try c.decode([ResearchStage].self, forKey:.stages); evidence=try c.decode([EvidenceItem].self, forKey:.evidence); hypotheses=try c.decode([HypothesisItem].self, forKey:.hypotheses); requirements=try c.decode([RequirementItem].self, forKey:.requirements)
        documents=try c.decodeIfPresent([SourceDocument].self, forKey:.documents) ?? []; chapterDraft=try c.decode(String.self, forKey:.chapterDraft)
    }

    static let empty = ThesisProject(title: "Untitled thesis", degree: "Degree not selected", locale: "English", researchQuestion: "Define the research question", stages: [], evidence: [], hypotheses: [], requirements: [], documents: [], chapterDraft: "")
}
