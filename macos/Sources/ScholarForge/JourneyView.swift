import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JourneyView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var focusOnly = false
    @State private var selectedID: String?
    @State private var exporting = false
    var openChapter: (Int) -> Void
    private var selectedIndex: Int? { store.journeyLinks.firstIndex { $0.id == selectedID } }
    private var filtered: [JourneyLink] {
        store.journeyLinks.filter { (!focusOnly || $0.priority || !AcademicJourney.isCurrent($0, chapters: store.manuscript.chapters)) && (query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("From insight to action").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("Concept → Passage → Evidence → Decision → Limitation").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save journey", systemImage: "square.and.arrow.down") { store.persistJourney() }.buttonStyle(.borderedProminent)
                Button("Export notes", systemImage: "square.and.arrow.up") { exporting = true }
            }
            Text("Traceable working notes • Links are not proof. Filling every field is not academic approval.")
                .font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                TextField("Find a concept, passage, source or decision", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Priority focus", isOn: $focusOnly).toggleStyle(.button)
                Button("Index new passages", systemImage: "arrow.triangle.branch") { store.indexNewJourneyPassages() }
                Button("Reconcile passages", systemImage: "arrow.triangle.2.circlepath") { store.reconcileJourneyPassages() }
            }
            HStack(spacing: 16) {
                Label("\(store.journeyLinks.count) passage links", systemImage: "link")
                Label("\(store.journeyLinks.filter { $0.missingCount > 0 }.count) incomplete chains", systemImage: "circle.dashed")
                Label("\(store.journeyLinks.filter { !AcademicJourney.isCurrent($0, chapters: store.manuscript.chapters) }.count) changed passages", systemImage: "exclamationmark.triangle")
            }.font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(filtered) { link in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(link.concept).font(.headline).lineLimit(3)
                            Text(link.chapterTitle).font(.caption).foregroundStyle(.secondary)
                            Label(link.priority ? "Priority chain" : "\(link.missingCount) fields to complete", systemImage: link.priority ? "star.fill" : "circle.dashed").font(.caption2)
                        }.padding(.vertical, 6).tag(link.id)
                    }
                }.frame(minWidth: 200, idealWidth: 250, maxWidth: 320)
                ScrollView {
                    if let index = selectedIndex {
                        detail(index).id(store.journeyLinks[index].id)
                    } else {
                        ContentUnavailableView("Explore a passage", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Choose a concept on the left. Evidence, decisions and limitations are yours to inspect and refine."))
                    }
                }.frame(minWidth: 320)
            }
            Text("Priority focus is a Pareto-style work queue, not a calculated 80/20 finding. Passage indexing is local and deterministic, not an AI council run.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedID)
            .onAppear { if let requested = store.requestedJourneyID { selectedID = requested; store.requestedJourneyID = nil } }
            .onChange(of: store.activeThesisPROProjectID) { selectedID = nil; query = ""; focusOnly = false }
            .fileExporter(isPresented: $exporting, document: JourneyNotesDocument(text: AcademicJourney.markdown(store.journeyLinks)), contentType: .plainText, defaultFilename: "ThesisPro-Journey.md") { result in
                if case .failure(let error) = result { store.importMessage = error.localizedDescription }
            }
    }

    private func field(_ title: String, _ hint: String, _ index: Int, _ key: WritableKeyPath<JourneyLink, String>) -> some View {
        let identity = store.journeyLinks[index].id
        let value = Binding<String>(get: {
            store.journeyLinks.first(where: { $0.id == identity })?[keyPath: key] ?? ""
        }, set: { text in
            guard let current = store.journeyLinks.firstIndex(where: { $0.id == identity }) else { return }
            store.journeyLinks[current][keyPath: key] = text
            store.journeyLinks[current].evidenceStatus = "needs_review"
        })
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(hint).font(.caption).foregroundStyle(.secondary)
            TextField(hint, text: value, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3...12)
        }
    }

    private func detail(_ index: Int) -> some View {
        let link = store.journeyLinks[index]
        return VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Working chain", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                Spacer()
                Toggle("Priority", isOn: Binding(get: { store.journeyLinks.first(where: { $0.id == link.id })?.priority ?? false }, set: { value in
                    if let current = store.journeyLinks.firstIndex(where: { $0.id == link.id }) { store.journeyLinks[current].priority = value }
                })).toggleStyle(.button)
            }
            field("1  Concept", "Name the idea this passage develops", index, \.concept)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("2  Thesis passage").font(.headline); Spacer(); Button("Open chapter") { openChapter(link.chapterIndex) } }
                Text(link.passage).font(.system(size: 14, design: .serif)).textSelection(.enabled)
                Label(AcademicJourney.isCurrent(link, chapters: store.manuscript.chapters) ? "Exact passage found in current chapter" : "Passage changed or removed. Reconcile this chain before using it.", systemImage: "doc.text.magnifyingglass").font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            Text(link.evidenceLabel).font(.callout).foregroundStyle(.secondary)
            field("3  Evidence", "Source, page or section, supporting extract, and what you checked", index, \.evidence)
            field("4  Decision", "Who acts, what changes, resources, alternatives and outcome measure", index, \.decision)
            field("5  Limitation", "Assumptions, contrary evidence and what remains untested", index, \.limitation)
            DisclosureGroup("Review desk: five questions") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Evidence: does the source actually support this passage?")
                    Text("Methods: do the design and measurements justify the inference?")
                    Text("Application: who benefits, who pays, and how would success be measured?")
                    Text("Challenge: what observation would weaken this argument?")
                    Text("Clarity: can a reader explain the idea and its limit simply?")
                    Text("A review checklist, not completed AI or human peer review.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            field("Review notes", "Record a specific issue, correction and unresolved disagreement", index, \.reviewNotes)
        }.padding(20)
    }
}

struct JourneyNotesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
