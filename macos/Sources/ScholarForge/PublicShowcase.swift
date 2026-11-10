import AppKit
import SwiftUI

struct PublicShowcaseEntry: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let degree: String
    let summary: String
    let question: String
    let stage: String
    let artwork: String
    let mergedInto: String?
}

struct PublicShowcaseCatalogue: Decodable {
    let schemaVersion: Int
    let title: String
    let notice: String
    let entries: [PublicShowcaseEntry]
    static func load() throws -> Self {
        guard let url = AppResources.url(forResource: "catalogue", withExtension: "json", subdirectory: "Showcase") else { throw CocoaError(.fileNoSuchFile) }
        let catalogue = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalogue.schemaVersion == 1, Set(catalogue.entries.map(\.id)).count == catalogue.entries.count else { throw CocoaError(.coderReadCorrupt) }
        return catalogue
    }
}

private struct ShowcaseCover: View {
    let entry: PublicShowcaseEntry
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary) }
        }.aspectRatio(2 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Interpretive cover for " + entry.title)
            .task(id: entry.artwork) {
                guard !entry.artwork.contains(".."), !entry.artwork.hasPrefix("/") else { return }
                let name = (entry.artwork as NSString).deletingPathExtension
                let ext = (entry.artwork as NSString).pathExtension
                if let url = AppResources.url(forResource: name, withExtension: ext, subdirectory: "Showcase") { image = NSImage(contentsOf: url) }
            }
    }
}

struct PublicShowcaseView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var catalogue: PublicShowcaseCatalogue?
    @State private var error: String?
    @State private var selectedID: String?
    @State private var search = ""
    @State private var includeArchived = true
    @State private var creationRequest: NewPaperRequest?
    var onCreated: () -> Void
    private var entries: [PublicShowcaseEntry] {
        (catalogue?.entries ?? []).filter { (includeArchived || $0.mergedInto == nil) && (search.isEmpty || "\($0.title) \($0.author) \($0.degree)".localizedStandardContains(search)) }
    }
    private var selected: PublicShowcaseEntry? { entries.first { $0.id == selectedID } ?? entries.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(catalogue?.title ?? "Research showcase").font(.system(size: 27, weight: .medium, design: .serif))
                    Text("Explore the questions. Start your own work.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("New paper", systemImage: "plus") { creationRequest = NewPaperRequest() }.buttonStyle(.borderedProminent)
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Search the collection", text: $search).textFieldStyle(.roundedBorder)
                    HStack {
                        Text("\(entries.count) original records").font(.headline)
                        Spacer()
                        Toggle("Include archived", isOn: $includeArchived).font(.caption)
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 18)], spacing: 22) {
                            ForEach(entries) { entry in
                                Button { selectedID = entry.id } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        ShowcaseCover(entry: entry)
                                        Text(entry.title).font(.system(size: 15, weight: .medium, design: .serif)).lineLimit(3).frame(height: 58, alignment: .topLeading)
                                        Text(entry.mergedInto == nil ? entry.degree : "Archived source record").font(.caption).foregroundStyle(.secondary)
                                    }.padding(12).background(selected?.id == entry.id ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected?.id == entry.id ? Color.accentColor : Color.secondary.opacity(0.15)))
                                }.buttonStyle(.plain)
                            }
                        }.padding(4)
                    }
                }.padding(20).frame(minWidth: 430)
                ScrollView {
                    if let entry = selected {
                        VStack(alignment: .leading, spacing: 18) {
                            ShowcaseCover(entry: entry).frame(maxHeight: 270).frame(maxWidth: .infinity)
                            Text(entry.title).font(.system(size: 24, weight: .medium, design: .serif))
                            if !entry.author.isEmpty { Text(entry.author).font(.callout).foregroundStyle(.secondary) }
                            Text(entry.stage).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            if let merged = entry.mergedInto {
                                Label("Preserved original", systemImage: "archivebox").font(.headline)
                                Text("This source record is part of another programme. It is not counted as an additional active paper.").font(.callout)
                                Button("Show canonical programme") { includeArchived = true; search = ""; selectedID = merged }
                            }
                            Text(entry.summary).font(.callout).textSelection(.enabled)
                            Divider()
                            Text("Research question").font(.headline)
                            Text(entry.question).font(.callout).textSelection(.enabled)
                            Button("Use this direction", systemImage: "square.and.pencil") { creationRequest = NewPaperRequest(title: entry.title, degree: entry.degree) }
                                .buttonStyle(.borderedProminent).disabled(entry.mergedInto != nil)
                            Text("Creates a new, empty personal project after you confirm its details. It does not copy a manuscript, evidence, results or author identity.").font(.caption).foregroundStyle(.secondary)
                        }.padding(24)
                    } else { ContentUnavailableView("No matching records", systemImage: "books.vertical") }
                }.frame(minWidth: 300, idealWidth: 350, maxWidth: 440).background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                if let error { Text(error).foregroundStyle(.red) }
                Text(catalogue?.notice ?? "Curated project summaries and interpretive artwork. This showcase is not a collection of approved theses.")
                Text("Your own manuscripts remain separate. Nothing is imported automatically.")
            }.font(.caption).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 850, idealWidth: 1160, minHeight: 690, idealHeight: 850)
            .task { do { catalogue = try PublicShowcaseCatalogue.load() } catch { self.error = "The bundled showcase could not be loaded. You can still create a new paper." } }
            .sheet(item: $creationRequest) { request in
                NewPaperView(initialTitle: request.title, initialDegree: request.degree) {
                    creationRequest = nil
                    dismiss()
                    onCreated()
                }.id(request.id).environment(store)
            }
    }
}

struct NewPaperView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author = ""
    @State private var degree: String
    @State private var targetWords = 20000
    @State private var question = ""
    @State private var error: String?
    var onCreated: () -> Void
    init(initialTitle: String = "", initialDegree: String = "Master's", onCreated: @escaping () -> Void) {
        _title = State(initialValue: initialTitle)
        _degree = State(initialValue: NewPaperRequest(degree: initialDegree).degree)
        self.onCreated = onCreated
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Start a new paper").font(.title2.weight(.semibold))
            Text("Your title, your evidence, your research record.").foregroundStyle(.secondary)
            Form {
                TextField("Title", text: $title)
                TextField("Author (optional)", text: $author)
                Picker("Programme", selection: $degree) { Text("Master's").tag("Master's"); Text("PhD").tag("PhD"); Text("Research paper").tag("Research paper") }
                TextField("Planning word target", value: $targetWords, format: .number)
                TextField("Research question (optional)", text: $question, axis: .vertical).lineLimit(3...5)
            }
            Text("The word target is a planning preference, not an institutional requirement. Six empty chapters are created; no findings or approval are assumed.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create paper") {
                    do { try store.createPersonalPaper(title: title, author: author, degree: degree, targetWords: targetWords, question: question); onCreated() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 560)
    }
}
