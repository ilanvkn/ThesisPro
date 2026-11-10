import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class ProjectStore {
    var project: ThesisProject
    var manuscript: ManuscriptProject
    var selectedChapterID: ManuscriptChapter.ID? {
        didSet {
            if let projectID = activeThesisPROProjectID, let chapter = manuscript.chapters.first(where: { $0.id == selectedChapterID }) {
                UserDefaults.standard.set(chapter.title, forKey: "thesisplus.chapter." + projectID)
            }
        }
    }
    var requestedJourneyID: String?
    var continuityMessage = "Reading history starts on this Mac."
    var languageLayer: LanguageLayer?
    var selection: WorkspaceSection? = .overview
    var searchText = ""
    var lastSaved: Date?
    var importMessage: String?
    var literatureResults: [LiteratureResult] = []
    var isSearchingLiterature = false
    var thesisPROProjects: [ThesisPROProjectSummary] = []
    var activeThesisPROProjectID: String?
    var journeyLinks: [JourneyLink] = []
    var journeyEditions: [JourneyEdition] = []
    private var loadedJourneyLinks: [JourneyLink] = []
    private var pendingJourneyArchive: [JourneyLink] = []
    var hasJourneyEdits: Bool { journeyLinks != loadedJourneyLinks }
    private var loadedProjectData: Data?
    private var loadedChapterText: [String] = []
    private var displayChapterText: [String] = []
    var selectedTypesetContent: String {
        guard let index = selectedChapterIndex else { return "" }
        let current = manuscript.chapters[index].content
        guard loadedChapterText.indices.contains(index), displayChapterText.indices.contains(index), current == loadedChapterText[index] else { return current }
        return displayChapterText[index]
    }
    var hasUnsavedChanges: Bool { activeThesisPROProjectID != nil && (manuscript.chapters.map(\.content) != loadedChapterText || hasJourneyEdits) }

    func reloadExternalManuscript() {
        guard let id = activeThesisPROProjectID,
              !hasJourneyEdits,
              manuscript.chapters.map(\.content) == loadedChapterText,
              let summary = thesisPROProjects.first(where: { $0.id == id }),
              let current = try? Data(contentsOf: summary.fileURL), current != loadedProjectData else { return }
        let selectedIndex = selectedChapterIndex
        openThesisPROProject(id)
        if let selectedIndex, manuscript.chapters.indices.contains(selectedIndex) {
            selectedChapterID = manuscript.chapters[selectedIndex].id
        }
    }
    private let saveURL: URL
    private let manuscriptURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ScholarForge", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        saveURL = base.appending(path: "project.json")
        manuscriptURL = base.appending(path: "manuscript.json")
        if let data = try? Data(contentsOf: saveURL), let saved = try? JSONDecoder().decode(ThesisProject.self, from: data) {
            project = saved
        } else { project = .empty }
        if let data = try? Data(contentsOf: manuscriptURL), let saved = try? JSONDecoder().decode(ManuscriptProject.self, from: data), saved.totalWords > 100 {
            manuscript = saved
        } else if let url = AppResources.url(forResource: "seed-thesis", withExtension: "json"), let data = try? Data(contentsOf: url), let seeded = try? JSONDecoder().decode(ManuscriptProject.self, from: data) {
            manuscript = seeded
        } else {
            manuscript = ManuscriptProject(title: "Untitled Thesis", degree: "Doctor of Philosophy", author: "Researcher", targetWords: 40000, chapters: [.init(title: "Chapter 1 Introduction", content: "Start writing here.", targetWords: 8000)])
        }
        selectedChapterID = manuscript.chapters.first?.id
    }

    func save() {
        do {
            try JSONEncoder().encode(project).write(to: saveURL, options: .atomic)
            try JSONEncoder().encode(manuscript).write(to: manuscriptURL, options: .atomic)
            if saveToThesisPRO() { lastSaved = .now }
        } catch { importMessage = "Could not save: \(error.localizedDescription)" }
    }

    /// Explicit creation writes a new UUID folder only; catalogue entries never become user manuscripts automatically.
    func createPersonalPaper(title: String, author: String, degree: String, targetWords: Int, question: String) throws {
        guard !hasUnsavedChanges else { throw PaperCreationError.unsavedChanges }
        let id = try PersonalPaperDraft(title: title, author: author, degree: degree, targetWords: targetWords, question: question).create(in: thesisPRORoot)
        Task {
            while isRefreshingLibrary {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            UserDefaults.standard.set(id, forKey: "thesisplus.lastProject")
            refreshThesisPROProjects(selectNewest: true)
        }
    }

    private var thesisPRORoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/ThesisPRO", directoryHint: .isDirectory)
    }

    var isRefreshingLibrary = false
    func refreshThesisPROProjects(selectNewest: Bool = false) {
        guard !isRefreshingLibrary else { return }
        isRefreshingLibrary = true
        let root = thesisPRORoot
        Task {
            let refreshed = await Task.detached(priority: .utility) { Self.scanLibrary(root) }.value
            defer { isRefreshingLibrary = false }
        if refreshed != thesisPROProjects { thesisPROProjects = refreshed }
        if selectNewest, let newest = thesisPROProjects.first {
            let previous = UserDefaults.standard.string(forKey: "thesisplus.lastProject")
            openThesisPROProject(thesisPROProjects.first(where: { $0.id == previous })?.id ?? newest.id)
        } else if let activeThesisPROProjectID,
                  !thesisPROProjects.contains(where: { $0.id == activeThesisPROProjectID }) {
            self.activeThesisPROProjectID = nil
        }
        if !selectNewest { reloadExternalManuscript() }
        if let summary = thesisPROProjects.first(where: { $0.id == activeThesisPROProjectID }) {
            let layer = LanguageLayer.load(projectFile: summary.fileURL)
            if languageLayer != layer { languageLayer = layer }
        } else { languageLayer = nil }
        }
    }

    nonisolated private static func scanLibrary(_ root: URL) -> [ThesisPROProjectSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let refreshed: [ThesisPROProjectSummary] = files.compactMap { folder in
            // Retain original projects on disk while presenting their canonical merged project.
            let statusFile = folder.appending(path: "library-status.json")
            if let statusData = try? Data(contentsOf: statusFile),
               let status = try? JSONSerialization.jsonObject(with: statusData) as? [String: String],
               let canonical = status["merged_into"],
               FileManager.default.fileExists(atPath: root.appending(path: canonical).appending(path: "project.json").path) { return nil }
            let file = folder.appending(path: "project.json")
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  let title = object["title"] as? String else { return nil }
            return ThesisPROProjectSummary(
                id: id,
                title: title,
                degree: object["degree"] as? String ?? "PhD",
                targetWords: object["target_words"] as? Int ?? 40_000,
                fileURL: file,
                draftWords: (object["chapters"] as? [[String: Any]] ?? []).filter {
                    !(($0["title"] as? String ?? "").localizedCaseInsensitiveContains("references"))
                }.reduce(0) { total, chapter in
                    let sections = chapter["sections"] as? [String: [String: Any]] ?? [:]
                    if let draft = sections["Mac application draft"]?["content"] as? String { return total + ManuscriptChapter.countWords(draft) }
                    return total + sections.values.reduce(0) { $0 + ManuscriptChapter.countWords($1["content"] as? String ?? "") }
                }
            )
        }.sorted { left, right in
            let l = (try? left.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? right.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }


        return refreshed
    }

    func openThesisPROProject(_ id: String) {
        guard !hasUnsavedChanges else {
            importMessage = "You have unsaved chapter edits. Save or copy them before opening another manuscript."
            return
        }
        guard let summary = thesisPROProjects.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: summary.fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawChapters = object["chapters"] as? [[String: Any]] else { return }

        displayChapterText = rawChapters.map { raw in
            let sections = raw["sections"] as? [String: [String: Any]] ?? [:]
            return sections.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending }.compactMap { key -> String? in
                guard let text = sections[key]?["content"] as? String, !text.isEmpty else { return nil }
                if key == "Mac application draft" || key == "Recovered working draft" { return text }
                let parts = text.components(separatedBy: "\n")
                let first = (parts.first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                let duplicate = first == key || key.hasSuffix(first) && !first.isEmpty
                let body = duplicate ? parts.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) : text
                return "## " + key + "\n\n" + body
            }.joined(separator: "\n\n")
        }
        let chapters = rawChapters.compactMap { raw -> ManuscriptChapter? in
            guard let number = raw["number"] as? Int,
                  let title = raw["title"] as? String else { return nil }
            let sections = raw["sections"] as? [String: [String: Any]] ?? [:]
            let order = SectionPreservingEdit.orderedKeys(sections)
            let compiled = order.compactMap { sections[$0]?["content"] as? String }.joined(separator: "\n\n")
            return ManuscriptChapter(
                title: title.localizedCaseInsensitiveContains("references") || title.hasPrefix("Chapter ") ? title : "Chapter \(number): \(title)",
                content: compiled,
                targetWords: raw["target_words"] as? Int ?? 0
            )
        }
        guard !chapters.isEmpty else { return }
        activeThesisPROProjectID = id
        languageLayer = LanguageLayer.load(projectFile: summary.fileURL)
        manuscript = ManuscriptProject(
            title: summary.title,
            degree: object["programme"] as? String ?? summary.degree,
            author: object["author"] as? String ?? "Researcher",
            targetWords: summary.targetWords,
            chapters: chapters
        )
        let rememberedTitle = UserDefaults.standard.string(forKey: "thesisplus.chapter." + id)
        selectedChapterID = manuscript.chapters.first(where: { $0.title == rememberedTitle })?.id ?? manuscript.chapters.first?.id
        UserDefaults.standard.set(id, forKey: "thesisplus.lastProject")
        requestedJourneyID = nil
        let historyKey = "thesisplus.fingerprints." + id
        let fingerprints = ReadingHistory.fingerprints(chapters)
        if let previous = UserDefaults.standard.dictionary(forKey: historyKey) as? [String: String] {
            let count = ReadingHistory.changed(previous, fingerprints)
            continuityMessage = count == 0 ? "No chapter text changes since the previous opening on this Mac." : "\(count) chapter entries changed since the previous opening on this Mac. This compares text, not research validity."
        } else { continuityMessage = "First recorded opening on this Mac. A chapter comparison baseline has been saved." }
        UserDefaults.standard.set(fingerprints, forKey: historyKey)
        loadedProjectData = data
        loadedChapterText = manuscript.chapters.map(\.content)
        if let raw = object["academic_journey"],
           let encoded = try? JSONSerialization.data(withJSONObject: raw),
           let saved = try? JSONDecoder().decode([JourneyLink].self, from: encoded) {
            journeyLinks = saved
        } else { journeyLinks = AcademicJourney.extract(projectID: id, chapters: chapters) }
        loadedJourneyLinks = journeyLinks
        pendingJourneyArchive = []
        journeyEditions = (object["reading_exports"] as? [[String: Any]] ?? []).compactMap { entry -> JourneyEdition? in
            guard let path = entry["path"] as? String, path.hasSuffix(".pdf"),
                  entry["stale_for_current_manuscript"] as? Bool != true,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return JourneyEdition(title: entry["kind"] as? String ?? URL(fileURLWithPath: path).lastPathComponent, path: path)
        }.reduce(into: [JourneyEdition]()) { list, item in if !list.contains(where: { $0.path == item.path }) { list.append(item) } }
        project = .empty
        project.title = summary.title
        project.degree = summary.degree
        project.locale = object["language"] as? String ?? "English"
        if let design = object["research_design"] as? [String: Any] {
            project.researchQuestion = (design["questions"] as? [String])?.first
                ?? design["aim"] as? String
                ?? "Research foundation in progress"
        }
        importMessage = nil
    }

    private func saveToThesisPRO() -> Bool {
        if activeThesisPROProjectID == nil { return true }
        if !hasUnsavedChanges { return true }
        guard let id = activeThesisPROProjectID,
              let summary = thesisPROProjects.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: summary.fileURL),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var chapters = object["chapters"] as? [[String: Any]] else {
            importMessage = "The shared project could not be read. Your local editor copy is retained."
            return false
        }

        guard data == loadedProjectData else {
            importMessage = "The manuscript changed in another session. Your editor text is retained; copy your changes before reloading to avoid overwriting the newer version."
            return false
        }

        for index in chapters.indices where index < manuscript.chapters.count {
            let chapter = manuscript.chapters[index]
            guard index >= loadedChapterText.count || chapter.content != loadedChapterText[index] else { continue }
            do {
                chapters[index]["sections"] = try SectionPreservingEdit.apply(chapter.content, to: chapters[index]["sections"] as? [String: [String: Any]] ?? [:])
            } catch { importMessage = error.localizedDescription; return false }
        }
        object["chapters"] = chapters
        if let encoded = try? JSONEncoder().encode(journeyLinks), let raw = try? JSONSerialization.jsonObject(with: encoded) { object["academic_journey"] = raw }
        if !pendingJourneyArchive.isEmpty,
           let encoded = try? JSONEncoder().encode(pendingJourneyArchive),
           let archived = try? JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] {
            var history = object["academic_journey_history"] as? [[String: Any]] ?? []
            history += archived
            object["academic_journey_history"] = history
        }
        object["academic_journey_schema"] = 2
        object["updated_at"] = ISO8601DateFormatter().string(from: .now)
        guard JSONSerialization.isValidJSONObject(object),
              let updated = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            let history = summary.fileURL.deletingLastPathComponent().appending(path: "history", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            try data.write(to: history.appending(path: "before-thesisplus-\(UUID().uuidString).json"), options: .atomic)
            try updated.write(to: summary.fileURL, options: .atomic)
        } catch {
            importMessage = "The shared save failed: \(error.localizedDescription). Your editor copy is retained."
            return false
        }
        loadedProjectData = updated
        loadedChapterText = manuscript.chapters.map(\.content)
        loadedJourneyLinks = journeyLinks
        pendingJourneyArchive = []
        return true
    }

    func indexNewJourneyPassages() {
        guard let id = activeThesisPROProjectID else { return }
        let known = Set(journeyLinks.map(\.id))
        journeyLinks += AcademicJourney.extract(projectID: id, chapters: manuscript.chapters).filter { !known.contains($0.id) }
    }

    func reconcileJourneyPassages() {
        guard let id = activeThesisPROProjectID else { return }
        let result = AcademicJourney.reconcile(projectID: id, chapters: manuscript.chapters, saved: journeyLinks)
        pendingJourneyArchive += result.archived
        journeyLinks = result.current
        importMessage = "Current passages indexed. \(result.archived.count) outdated records will be preserved in history when you save. Changed passages require a new evidence review."
    }

    func persistJourney() {
        // Persist even the first generated index without manufacturing an edit.
        loadedJourneyLinks = []
        save()
    }

    func resetDemo() { project = .empty; save() }

    func copySelectedChapter() {
        guard let chapter = selectedChapter else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(chapter.content, forType: .string)
        importMessage = "Copied \(chapter.wordCount.formatted()) words from \(chapter.title)."
    }

    var selectedChapterIndex: Int? { manuscript.chapters.firstIndex { $0.id == selectedChapterID } }
    var selectedChapter: ManuscriptChapter? { selectedChapterIndex.map { manuscript.chapters[$0] } }

    func importDocuments(_ urls: [URL]) async {
        var imported = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try DocumentIngestion.extractText(from: url)
                let source = SourceDocument(filename: url.lastPathComponent, kind: url.pathExtension.uppercased(), text: text, citations: CitationExtractor.extract(from: text))
                project.documents.removeAll { $0.filename == source.filename }
                project.documents.append(source); imported += 1
            } catch { importMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        if imported > 0 { importMessage = "Imported and indexed \(imported) document\(imported == 1 ? "" : "s")."; save() }
    }

    func searchLiterature(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearchingLiterature = true; defer { isSearchingLiterature = false }
        do { literatureResults = try await CrossrefService.search(query: query) }
        catch { importMessage = "Literature search failed: \(error.localizedDescription)" }
    }

    func addEvidence(from result: LiteratureResult) {
        guard !project.evidence.contains(where: { $0.citation == result.citation }) else { return }
        project.evidence.append(.init(citation: result.citation, finding: "Finding requires full-text verification.", use: "Imported from discovery; do not cite substantively until verified.", verified: false)); save()
    }

    func exportChapter(to url: URL) throws { try ChapterExporter.write(project: project, to: url) }
}
