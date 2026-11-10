import Foundation
import CryptoKit

struct LanguageLayer: Codable, Equatable {
    let baselineWords: Int
    let sourceWords: Int
    let reviewedWords: Int
    let chapterNumber: Int
    let sourceHash: String
    let draftHash: String
    let draftFile: String
    let scope: String
    let blockers: String
    var text: String = ""
    var valid: Bool = false
    enum CodingKeys: String, CodingKey {
        case baselineWords, sourceWords, reviewedWords, chapterNumber, sourceHash, draftHash, draftFile, scope, blockers
    }
    var coverage: Double { valid && baselineWords > 0 ? min(1, Double(max(0, sourceWords)) / Double(baselineWords)) : 0 }
    var reviewed: Double { valid && baselineWords > 0 ? min(coverage, Double(max(0, reviewedWords)) / Double(baselineWords)) : 0 }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func load(projectFile: URL) -> LanguageLayer? {
        let folder = projectFile.deletingLastPathComponent().appending(path: "language-layer")
        guard let data = try? Data(contentsOf: folder.appending(path: "progress.json")),
              var layer = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        guard layer.draftFile == URL(fileURLWithPath: layer.draftFile).lastPathComponent,
              let draft = try? String(contentsOf: folder.appending(path: layer.draftFile), encoding: .utf8),
              let projectData = try? Data(contentsOf: projectFile),
              let object = try? JSONSerialization.jsonObject(with: projectData) as? [String: Any],
              let chapters = object["chapters"] as? [[String: Any]],
              let chapter = chapters.first(where: { $0["number"] as? Int == layer.chapterNumber }),
              let sections = chapter["sections"] as? [String: [String: Any]] else { return layer }
        let source = SectionPreservingEdit.orderedKeys(sections).compactMap { sections[$0]?["content"] as? String }.joined(separator: "\n\n")
        layer.text = draft
        layer.valid = hash(source) == layer.sourceHash && hash(draft) == layer.draftHash
        return layer
    }
}
