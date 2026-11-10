import Foundation

struct ChapterFocus: Identifiable {
    let id: UUID
    let index: Int
    let title: String
    let words: Int
    let target: Int
    let share: Double
    let links: Int
    let missingEvidence: Int
    var balance: String {
        guard target > 0 else { return "No budget set" }
        let ratio = Double(words) / Double(target)
        return ratio < 0.8 ? "Below planned length" : ratio > 1.2 ? "Above planned length" : "Near planned length"
    }
}

enum ThesisMapAnalysis {
    static func chapters(_ manuscript: ManuscriptProject, links: [JourneyLink]) -> [ChapterFocus] {
        let body = manuscript.chapters.enumerated().filter { !$0.element.title.localizedCaseInsensitiveContains("references") && !$0.element.title.localizedCaseInsensitiveContains("appendix") }
        let total = body.reduce(0) { $0 + $1.element.wordCount }
        return body.map { index, chapter in
            let associated = links.filter { $0.chapterIndex == index }
            return ChapterFocus(id: chapter.id, index: index, title: chapter.title, words: chapter.wordCount, target: chapter.targetWords, share: total > 0 ? Double(chapter.wordCount) / Double(total) : 0, links: associated.count, missingEvidence: associated.filter { $0.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
        }
    }
}
