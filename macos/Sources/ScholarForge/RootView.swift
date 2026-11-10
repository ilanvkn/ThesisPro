import SwiftUI
import UniformTypeIdentifiers

enum EditorMode: String, CaseIterable { case map = "Thesis map", journey = "Journey", preview = "Preview", write = "Write", reading = "Reading", presentation = "Presentation" }

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @State private var mode: EditorMode = .map
    @AppStorage("thesisplus.appearance") private var appearance = "Light"
    @AppStorage("thesisplus.showInspector") private var showInspector = true
    @Environment(\.openSettings) private var openSettings
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingBookshelf = true
    @State private var pdfPreview: PDFPreviewPayload?

    var body: some View {
        @Bindable var store = store
        Group {
        if mode == .reading {
            ThesisReadingView()
        } else if mode == .presentation || mode == .map {
            VStack(spacing: 0) {
                thesisPROProjectPicker.padding(.top, 12)
                ThesisMapView(presentation: mode == .presentation, openJourney: { mode = .journey }) { index in
                    if store.manuscript.chapters.indices.contains(index) { store.selectedChapterID = store.manuscript.chapters[index].id; mode = .reading }
                }
            }
        } else {
        NavigationSplitView {
            VStack(spacing: 0) {
                projectIdentity
                thesisPROProjectPicker
                List(selection: $store.selectedChapterID) {
                    Section("Manuscript") { ForEach(store.manuscript.chapters.filter { store.searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(store.searchText) || $0.content.localizedCaseInsensitiveContains(store.searchText) }) { chapter in ChapterRow(chapter: chapter).tag(chapter.id) } }
                }
                TextField("Search chapter text", text: $store.searchText).textFieldStyle(.roundedBorder).padding(12)
                totalProgress
            }.navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
        } content: {
            documentSurface.navigationSplitViewColumnWidth(min: 520, ideal: 760)
        } detail: {
            if showInspector { ThesisInspector().navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 380) }
        }
        }
        }
        .onExitCommand { mode = .map }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Workspace", selection: $mode) { ForEach(EditorMode.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.menu).frame(width: 175)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Workspace preferences", systemImage: "slider.horizontal.3") { openSettings() }
                Menu("Appearance", systemImage: "circle.lefthalf.filled") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                        Text("Follow system").tag("System")
                    }
                }
                Button("Bookshelf", systemImage: "books.vertical") { store.refreshThesisPROProjects(); showingBookshelf = true }
                Button("Refresh ThesisPro", systemImage: "arrow.clockwise") { store.refreshThesisPROProjects() }.help("Find projects created from Codex or ChatGPT")
                Button("Import Sources", systemImage: "doc.badge.plus") { showingImporter = true }.help("Import research documents")
                Button("Copy Chapter", systemImage: "doc.on.doc") { store.copySelectedChapter() }.help("Copy the visible chapter")
                Menu("Saved editions", systemImage: "books.vertical.fill") {
                    ForEach(store.journeyEditions) { edition in
                        Button(edition.title) {
                            if let data = try? Data(contentsOf: URL(fileURLWithPath: edition.path)) { pdfPreview = PDFPreviewPayload(data: data, title: edition.title) }
                            else { store.importMessage = "This saved edition could not be opened." }
                        }
                    }
                    Text("Versioned files, not automatic submission approval")
                }.disabled(store.journeyEditions.isEmpty)
                Button("Draft PDF", systemImage: "doc.richtext") {
                    pdfPreview = PDFPreviewPayload(data: ThesisPDFRenderer.render(store.manuscript), title: store.manuscript.title)
                }.help("Paginate the current manuscript and save a PDF copy")
                Button("Export Thesis", systemImage: "square.and.arrow.up") { showingExporter = true }.help("Export the whole thesis as Word")
                Button("Save", systemImage: "square.and.arrow.down") { store.save() }.keyboardShortcut("s", modifiers: .command)
            }
        }
        .task {
            showingBookshelf = UserDefaults.standard.object(forKey: "thesisplus.showLibraryAtLaunch") as? Bool ?? true
            await Task.yield()
            store.refreshThesisPROProjects(selectNewest: store.activeThesisPROProjectID == nil)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                store.refreshThesisPROProjects()
            }
        }
        .sheet(isPresented: $showingBookshelf) {
            ThesisBookshelf { destination in
                switch destination { case .reading: mode = .reading; case .map: mode = .map; case .journey: mode = .journey }
            }.environment(store)
        }
        .sheet(item: $pdfPreview) { preview in
            ThesisPDFSheet(data: preview.data, title: preview.title)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf, .plainText, .rtf, UTType(filenameExtension: "docx") ?? .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await store.importDocuments(urls) } }
        }
        .fileExporter(isPresented: $showingExporter, document: ManuscriptExportDocument(manuscript: store.manuscript), contentType: UTType(filenameExtension: "docx") ?? .data, defaultFilename: store.manuscript.title) { result in
            if case .failure(let error) = result { store.importMessage = error.localizedDescription }
        }
        .alert("ThesisPro", isPresented: Binding(get: { store.importMessage != nil }, set: { if !$0 { store.importMessage = nil } })) {
            Button("OK") { store.importMessage = nil }
        } message: { Text(store.importMessage ?? "") }
    }

    private var thesisPROProjectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THESISPRO LIBRARY").font(.caption2.bold()).foregroundStyle(.secondary)
            if store.thesisPROProjects.isEmpty {
                Text("No shared projects found").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Project", selection: Binding(
                    get: { store.activeThesisPROProjectID ?? "" },
                    set: { store.openThesisPROProject($0) }
                )) {
                    ForEach(store.thesisPROProjects) { project in
                        Text(project.title).tag(project.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var projectIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("THESISPRO", systemImage: "book.closed").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.tint)
            Text(store.manuscript.title).font(.headline).lineLimit(4)
            Text(store.manuscript.author).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalProgress: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("DRAFT LENGTH").font(.caption2.bold()); Spacer(); Text("\(store.manuscript.draftWords.formatted()) / \(store.manuscript.targetWords.formatted())").font(.caption.monospacedDigit()) }
            ProgressView(value: min(Double(store.manuscript.draftWords) / Double(max(store.manuscript.targetWords, 1)), 1))
            Text(store.manuscript.degree).font(.caption2).foregroundStyle(.secondary)
            Text("Excludes reference chapters; includes headings. Review pending.").font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(.bar)
    }

    @ViewBuilder private var documentSurface: some View {
        if mode == .journey {
            JourneyView { index in
                if store.manuscript.chapters.indices.contains(index) { store.selectedChapterID = store.manuscript.chapters[index].id; mode = .preview }
            }
        } else if let index = store.selectedChapterIndex {
            VStack(spacing: 0) {
                chapterHeader(index: index)
                Divider()
                if mode == .write {
                    let chapterID = store.manuscript.chapters[index].id
                    TextEditor(text: Binding(
                        get: { store.manuscript.chapters.first(where: { $0.id == chapterID })?.content ?? "" },
                        set: { text in
                            if let current = store.manuscript.chapters.firstIndex(where: { $0.id == chapterID }) { store.manuscript.chapters[current].content = text }
                        }
                    ))
                        .font(.system(size: 15, design: .serif)).lineSpacing(7).padding(34)
                        .scrollContentBackground(.hidden).background(Color(nsColor: .textBackgroundColor))
                } else {
                    ScrollView {
                        TypesetChapter(text: store.manuscript.chapters[index].content)
                            .frame(maxWidth: 690, alignment: .leading).padding(.horizontal, 64).padding(.vertical, 48)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 3).padding(32)
                    }.background(Color(nsColor: .underPageBackgroundColor))
                }
            }
        } else { ContentUnavailableView("Choose a chapter", systemImage: "doc.text", description: Text("Select a chapter from the manuscript sidebar.")) }
    }

    private func chapterHeader(index: Int) -> some View {
        let chapter = store.manuscript.chapters[index]
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) { Text(chapter.title).font(.title2.bold()); Text(store.hasUnsavedChanges ? "Unsaved edits — save before switching projects" : "Shared ThesisPRO manuscript · local copy").font(.caption).foregroundStyle(.secondary) }
            Spacer(); Text("\(chapter.wordCount.formatted()) words").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.vertical, 14).background(.bar)
    }
}

struct ChapterRow: View {
    let chapter: ManuscriptChapter
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(chapter.title).fontWeight(.medium).lineLimit(2)
            HStack { Text("\(chapter.wordCount.formatted()) words"); Spacer(); Text("\(Int(min(Double(chapter.wordCount) / Double(max(chapter.targetWords, 1)), 1) * 100))%") }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct ThesisInspector: View {
    @Environment(ProjectStore.self) private var store
    var qualityRequirements: [RequirementItem] {
        if store.activeThesisPROProjectID != nil {
            return [
                .init(text: "Maintain alignment among the problem, gap, aim, objectives, questions, method, and contribution", met: false),
                .init(text: "Support externally verifiable claims with checked scholarly sources", met: false),
                .init(text: "Separate prior evidence, researcher interpretation, and original contribution", met: false),
                .init(text: "Verify that empirical claims match collected data and analysis", met: false),
                .init(text: "Run an integrity and evidence audit before approving each chapter", met: false)
            ]
        }
        return store.project.requirements
    }
    var guidance: [String] {
        let title = store.selectedChapter?.title ?? ""
        if store.activeThesisPROProjectID?.contains("human-ai") == true {
            return ["Distinguish proposed design principles from verified findings.", "Compare the argument with specific sources and contrary evidence.", "Record assumptions, test conditions, and observed results.", "State what the evidence establishes and what remains unresolved."]
        }
        if title.contains("Chapter 5") { return ["State the novelty and contribution.", "Explain why the mediation pattern may occur in Sabah.", "Connect claims to evidence on parenting and community support.", "Specify a family-based JPNS intervention.", "Separate findings, interpretation, and recommendations."] }
        if title.contains("Chapter 4") { return ["Report results without explaining why they occurred.", "Match every number to the statistical output.", "Include effect sizes and confidence intervals.", "Use tables only where comparison helps."] }
        if title.contains("Chapter 3") { return ["Make the design reproducible.", "Explain sampling and inclusion criteria.", "Document measures, validity, ethics, and analysis choices."] }
        if title.contains("Chapter 2") { return ["Synthesize studies by argument, not author-by-author.", "Identify disagreement and the precise research gap.", "Connect the literature to the conceptual model."] }
        return ["Define the problem and research gap.", "State objectives, questions, and hypotheses consistently.", "Explain the study’s significance without overstating it."]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What to write").font(.title2.bold())
                Text(store.selectedChapter?.title ?? "Select a chapter").foregroundStyle(.secondary)
                ForEach(Array(guidance.enumerated()), id: \.offset) { n, text in
                    HStack(alignment: .top, spacing: 10) { Text("\(n + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(.blue, in: Circle()); Text(text).fixedSize(horizontal: false, vertical: true) }
                }
                Divider(); Text(store.activeThesisPROProjectID == nil ? "Supervisor requirements" : "Project quality gates").font(.headline)
                ForEach(qualityRequirements) { item in Label(item.text, systemImage: item.met ? "checkmark.circle.fill" : "circle").foregroundStyle(item.met ? .green : .secondary).font(.callout) }
                Divider(); Button("Copy this chapter") { store.copySelectedChapter() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                Text("Switch to Write to edit. Preview shows the manuscript as a readable document page. Save keeps your changes on this Mac.").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.background(.regularMaterial)
    }
}

struct ManuscriptExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "docx") ?? .data] }
    let data: Data
    init(manuscript: ManuscriptProject) {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".docx")
        try? ChapterExporter.write(manuscript: manuscript, to: temp); data = (try? Data(contentsOf: temp)) ?? Data()
    }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
