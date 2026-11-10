import Foundation

enum PaperCreationError: LocalizedError {
    case unsavedChanges, invalidInput, conflictingFolder
    var errorDescription: String? {
        switch self {
        case .unsavedChanges: "Save your current manuscript before creating another paper."
        case .invalidInput: "Enter a title and a word target from 1 to 500,000."
        case .conflictingFolder: "The new project folder already exists. Please try again."
        }
    }
}

struct PersonalPaperDraft {
    let title: String
    let author: String
    let degree: String
    let targetWords: Int
    let question: String

    func create(in root: URL) throws -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, targetWords > 0, targetWords <= 500_000 else { throw PaperCreationError.invalidInput }
        let id = "paper-" + UUID().uuidString.lowercased()
        let folder = root.appending(path: id, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw PaperCreationError.conflictingFolder }
        let titles = ["Introduction", "Literature Review", "Methodology", "Results / Findings", "Discussion and Conclusion", "References and Appendices"]
        let ratios = [0.12, 0.28, 0.22, 0.20, 0.18, 0.0]
        var budgets = ratios.map { Int((Double(targetWords) * $0).rounded()) }
        budgets[4] += targetWords - budgets.reduce(0, +)
        let chapters: [[String: Any]] = titles.enumerated().map { i, name in
            ["number": i + 1, "title": name, "role": i == 5 ? "back_matter" : "main_text", "target_words": budgets[i], "sections": [String: Any]()]
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let object: [String: Any] = ["id": id, "title": cleanTitle, "author": author.trimmingCharacters(in: .whitespacesAndNewlines), "degree": degree, "discipline": "To be specified", "target_words": targetWords, "language": "English", "citation_style": "APA 7 (provisional)", "status": "Research foundation", "created_at": now, "updated_at": now, "research_design": ["questions": question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [question]], "chapters": chapters, "sources": [], "claims": [], "decisions": [], "notes": []]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { try data.write(to: folder.appending(path: "project.json"), options: .atomic) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return id
    }
}

/// One presentation request carries the initial values and a fresh sheet identity together.
struct NewPaperRequest: Identifiable {
    let id = UUID()
    let title: String
    let degree: String

    init(title: String = "", degree: String = "Master's") {
        self.title = title
        self.degree = ["Master's", "PhD", "Research paper"].contains(degree) ? degree : "Research paper"
    }
}
