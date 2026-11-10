import Foundation

@main
struct PersonalPaperTests {
    static func main() throws {
        let blank = NewPaperRequest()
        let mba = NewPaperRequest(title: "Human AI workplace", degree: "Master's")
        let phd = NewPaperRequest(title: "Tamil Time Continuum", degree: "PhD")
        precondition(blank.title.isEmpty && blank.degree == "Master's")
        precondition(mba.title == "Human AI workplace" && mba.degree == "Master's")
        precondition(phd.title == "Tamil Time Continuum" && phd.degree == "PhD")
        precondition(blank.id != mba.id && mba.id != phd.id)
        precondition(NewPaperRequest(degree: "Unknown").degree == "Research paper")
        let root = FileManager.default.temporaryDirectory.appending(path: "thesispro-creation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appending(path: "existing-user-record.txt")
        try Data("retain existing work".utf8).write(to: sentinel)
        let draft = PersonalPaperDraft(title: "My research", author: "", degree: "Research paper", targetWords: 12345, question: "What evidence supports this?")
        let first = try draft.create(in: root)
        let second = try draft.create(in: root)
        precondition(first != second)
        let data = try Data(contentsOf: root.appending(path: first).appending(path: "project.json"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(object["author"] as? String == "")
        precondition(object["title"] as? String == "My research")
        let chapters = object["chapters"] as! [[String: Any]]
        precondition(chapters.count == 6 && chapters.reduce(0) { $0 + ($1["target_words"] as! Int) } == 12345)
        precondition(chapters.allSatisfy { ($0["sections"] as! [String: Any]).isEmpty })
        precondition((object["sources"] as! [Any]).isEmpty && (object["claims"] as! [Any]).isEmpty)
        precondition(chapters.last?["role"] as? String == "back_matter")
        let preserved = try String(contentsOf: sentinel, encoding: .utf8)
        precondition(preserved == "retain existing work")
        for invalid in [PersonalPaperDraft(title: " ", author: "", degree: "PhD", targetWords: 100, question: ""), PersonalPaperDraft(title: "Title", author: "", degree: "PhD", targetWords: 0, question: "")] {
            do { _ = try invalid.create(in: root); fatalError("Invalid draft accepted") } catch PaperCreationError.invalidInput { }
        }
        print("Personal paper checks passed: unique creation, preserved existing work, blank author, empty evidence, planning budgets, invalid inputs.")
    }
}
