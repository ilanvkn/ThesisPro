import AppKit
import ImageIO
import SwiftUI

private struct LibraryShowcase: Decodable {
    let author: String?
    let tagline: String?
    let finding: String?
    let artworkNote: String?
    let stage: String?
}

private struct LibraryRecord {
    var author = "Author not recorded"
    var showcase: LibraryShowcase?
    var sources = 0
    var claims = 0
    var stage = "Research record"
    var hasOriginal = false
    var hasNewArtwork = false
}

enum LibraryDestination { case reading, map, journey }
enum LibraryFilter: String, CaseIterable {
    case all = "All degrees", masters = "Master's", phd = "PhD"
}

enum LibraryCatalogue {
    static func degree(_ item: ThesisPROProjectSummary) -> String {
        if item.degree.lowercased().contains("master") || item.degree.lowercased().contains("mba") { return "Master's" }
        if item.degree.lowercased().contains("phd") || item.degree.lowercased().contains("doctor") { return "PhD" }
        return item.degree
    }
    static func matches(_ item: ThesisPROProjectSummary, query: String, filter: LibraryFilter) -> Bool {
        let terms = (item.title + " " + item.degree + " " + degree(item)).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return (filter == .all || degree(item) == filter.rawValue) && query.split(whereSeparator: \.isWhitespace).allSatisfy {
            terms.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
        }
    }
    static func artworkName(for id: String) -> String? { nil }
}

struct LibraryCover: View {
    let item: ThesisPROProjectSummary
    var version = "latest"
    var refreshID = 0
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                LinearGradient(colors: [.accentColor.opacity(0.8), .accentColor.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 20) {
                    Image(systemName: "book.closed").font(.largeTitle)
                    Text(item.title).font(.system(size: 20, weight: .medium, design: .serif)).multilineTextAlignment(.center).lineLimit(6)
                    Text(LibraryCatalogue.degree(item)).font(.caption)
                }.foregroundStyle(.white).padding(22)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Interpretive artwork for " + item.title)
        .task(id: "\(item.fileURL.path)|\(version)|\(refreshID)") {
            // No URL-only global cache: replaced artwork must load on refresh and reopening.
            image = nil
            let folder = item.fileURL.deletingLastPathComponent()
            let names = version == "original"
                ? ["artwork-archive/bookshelf-before-v10.png", "bookshelf-artwork.png", "cover-concept.png"]
                : ["bookshelf-artwork.png", "bookshelf-artwork-v2.png", "bookshelf-artwork-v10.png", "cover-concept.png"]
            for name in names {
                guard !Task.isCancelled else { return }
                let url = folder.appending(path: name)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { continue }
                image = NSImage(cgImage: cg, size: .zero)
                break
            }
        }
    }
}

struct ThesisBookshelf: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("thesisplus.motion") private var motion = "Subtle"
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var grid = true
    @State private var selectedID: String?
    @State private var visible: [ThesisPROProjectSummary] = []
    @State private var records: [String: LibraryRecord] = [:]
    @State private var artworkPreferences: [String: String] = [:]
    @State private var refreshID = 0
    @State private var openingError: String?
    var open: (LibraryDestination) -> Void
    private var selected: ThesisPROProjectSummary? { visible.first { $0.id == selectedID } ?? visible.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                collection.frame(minWidth: 430, idealWidth: 680)
                inspector.frame(minWidth: 290, idealWidth: 350, maxWidth: 440)
            }
            Divider()
            HStack {
                Label("On this Mac", systemImage: "lock.shield")
                Spacer()
                Text("Cover artwork is interpretive. Evidence determines the claim.")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(minWidth: 850, idealWidth: 1180, minHeight: 690, idealHeight: 850)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { selectedID = store.activeThesisPROProjectID; reload() }
        .onChange(of: query) { filterRecords() }
        .onChange(of: filter) { filterRecords() }
        .onChange(of: store.thesisPROProjects) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "books.vertical").font(.system(size: 24, weight: .light)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("The research library").font(.system(size: 28, weight: .medium, design: .serif))
                Text("Independent papers. Connected ideas.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reload library artwork", systemImage: "arrow.clockwise") { reload() }.labelStyle(.iconOnly).help("Reload covers and saved research details")
            Button("Return to workspace", systemImage: "arrow.up.right") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24)
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Search title, author or degree", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Search research library")
                Picker("Degree", selection: $filter) {
                    ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue) }
                }.labelsHidden().frame(width: 140)
            }
            HStack {
                Text(visible.count == 1 ? "1 work" : "\(visible.count) works").font(.headline)
                Spacer()
                Picker("Collection layout", selection: $grid) {
                    Text("Gallery").tag(true)
                    Text("Shelf").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            if visible.isEmpty && store.isRefreshingLibrary {
                ProgressView("Opening your research library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                ContentUnavailableView("No matching papers", systemImage: "books.vertical", description: Text("Try another title, author or degree."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button("Clear search") { query = ""; filter = .all }
            } else if grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175, maximum: 235), spacing: 18)], alignment: .leading, spacing: 22) {
                        ForEach(visible) { item in coverButton(item) }
                    }.padding(4)
                }
            } else {
                shelf
                Spacer(minLength: 0)
            }
        }.padding(22)
    }

    private var shelf: some View {
        ScrollViewReader { reader in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button("Previous paper", systemImage: "chevron.left") { advance(-1, reader: reader) }.labelStyle(.iconOnly)
                    Text("\((visible.firstIndex { $0.id == selected?.id } ?? 0) + 1) of \(visible.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Next paper", systemImage: "chevron.right") { advance(1, reader: reader) }.labelStyle(.iconOnly)
                    Spacer()
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 22) {
                        ForEach(visible) { item in coverButton(item).frame(width: 230).id(item.id) }
                    }.padding(4)
                }
            }
        }
    }

    private func coverButton(_ item: ThesisPROProjectSummary) -> some View {
        let isSelected = selected?.id == item.id
        return Button {
            withAnimation(WorkspaceMotion.animation(motion, reduce: reduceMotion)) { selectedID = item.id }
            openingError = nil
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                LibraryCover(item: item, version: artworkPreferences[item.id] ?? "latest", refreshID: refreshID)
                    .shadow(color: .black.opacity(0.12), radius: 7, x: 1, y: 4)
                HStack {
                    Text(LibraryCatalogue.degree(item)).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Spacer()
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(item.title).font(.system(size: 15, weight: .medium, design: .serif)).lineLimit(3).frame(height: 58, alignment: .topLeading)
                Text(records[item.id]?.author ?? "Author not recorded").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
                Text("\(item.draftWords.formatted()) draft words").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1))
        }.buttonStyle(.plain).help("Inspect " + item.title)
        .accessibilityLabel("\(item.title), \(LibraryCatalogue.degree(item)), \(item.draftWords) draft words")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var inspector: some View {
        ScrollView {
            if let item = selected {
                let record = records[item.id] ?? LibraryRecord()
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("SELECTED WORK").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Spacer()
                        Text(LibraryCatalogue.degree(item)).font(.caption.weight(.medium))
                    }
                    LibraryCover(item: item, version: artworkPreferences[item.id] ?? "latest", refreshID: refreshID)
                        .frame(maxHeight: 280).frame(maxWidth: .infinity)
                    if record.hasOriginal || record.hasNewArtwork {
                        Picker("Cover edition", selection: artworkBinding(item.id)) {
                            Text("Latest").tag("latest")
                            if record.hasOriginal { Text("Original").tag("original") }
                        }.pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.system(size: 23, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                        Text(record.author).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        if item.title.localizedCaseInsensitiveContains("Tamil Time Continuum") {
                            Text("தமிழ் காலத் தொடர்ச்சி").font(.title3)
                            Text("Tamil name for this research project; not a claim of historical provenance.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let tagline = record.showcase?.tagline, !tagline.isEmpty {
                        Text(tagline).font(.system(size: 18, weight: .medium, design: .serif)).foregroundStyle(Color.accentColor)
                    }
                    HStack(spacing: 20) {
                        metric("Words", value: item.draftWords.formatted())
                        metric("Sources", value: record.sources.formatted())
                        metric("Claims", value: record.claims.formatted())
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Evidence at a glance", systemImage: "text.book.closed").font(.headline)
                        Text(record.showcase?.finding ?? "Open the evidence journey to inspect the saved claims, sources and unresolved questions.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(record.stage).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text("Counts describe saved records, not verified support or academic approval.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 9) {
                        Button { route(item, to: .reading) } label: { Label("Open manuscript", systemImage: "book.pages").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        HStack {
                            Button("Research map", systemImage: "point.3.connected.trianglepath.dotted") { route(item, to: .map) }
                            Button("Evidence", systemImage: "link") { route(item, to: .journey) }
                        }
                    }.controlSize(.large)
                    if let openingError { Text(openingError).font(.callout).foregroundStyle(.red) }
                    if let note = record.showcase?.artworkNote {
                        Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(24)
            } else {
                ContentUnavailableView("Choose a paper", systemImage: "book.closed", description: Text("Its author, findings and evidence will appear here."))
            }
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func artworkBinding(_ id: String) -> Binding<String> {
        Binding(get: { artworkPreferences[id] ?? "latest" }, set: { value in
            artworkPreferences[id] = value
            UserDefaults.standard.set(artworkPreferences, forKey: "thesispro.library.artworkPreferences")
        })
    }

    private func reload() {
        artworkPreferences = UserDefaults.standard.dictionary(forKey: "thesispro.library.artworkPreferences") as? [String: String] ?? [:]
        var next: [String: LibraryRecord] = [:]
        for item in store.thesisPROProjects {
            let folder = item.fileURL.deletingLastPathComponent()
            var record = LibraryRecord()
            if let data = try? Data(contentsOf: folder.appending(path: "showcase.json")) {
                record.showcase = try? JSONDecoder().decode(LibraryShowcase.self, from: data)
            }
            // Author identity is canonical project metadata, never borrowed from another cover.
            if let data = try? Data(contentsOf: item.fileURL), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let author = object["author"] as? String, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { record.author = author }
                record.sources = (object["sources"] as? [Any])?.count ?? 0
                record.claims = (object["claims"] as? [Any])?.count ?? 0
                record.stage = record.showcase?.stage ?? (object["research_stage"] as? String) ?? (object["status"] as? String) ?? "Research record"
            }
            record.hasOriginal = FileManager.default.fileExists(atPath: folder.appending(path: "artwork-archive/bookshelf-before-v10.png").path)
            record.hasNewArtwork = FileManager.default.fileExists(atPath: folder.appending(path: "bookshelf-artwork-v10.png").path)
            next[item.id] = record
        }
        records = next
        refreshID += 1
        filterRecords()
    }

    private func filterRecords() {
        visible = store.thesisPROProjects.filter { item in
            guard filter == .all || LibraryCatalogue.degree(item) == filter.rawValue else { return false }
            let text = "\(item.title) \(item.degree) \(LibraryCatalogue.degree(item)) \(records[item.id]?.author ?? "") \(item.title.localizedCaseInsensitiveContains("Tamil Time Continuum") ? "தமிழ் காலத் தொடர்ச்சி" : "")"
            return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains(String($0)) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !visible.contains(where: { $0.id == selectedID }) { selectedID = visible.first?.id }
    }

    private func advance(_ amount: Int, reader: ScrollViewProxy) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selected?.id } ?? 0
        let next = visible[(index + amount + visible.count) % visible.count].id
        withAnimation(WorkspaceMotion.animation(motion, reduce: reduceMotion)) { selectedID = next; reader.scrollTo(next, anchor: .center) }
    }

    private func route(_ item: ThesisPROProjectSummary, to destination: LibraryDestination) {
        if store.activeThesisPROProjectID != item.id {
            guard !store.hasUnsavedChanges else { openingError = "Your current thesis has unsaved edits. Return to the workspace and save them before switching."; return }
            store.openThesisPROProject(item.id)
            guard store.activeThesisPROProjectID == item.id else { openingError = "This project could not be opened. Refresh the library and try again."; return }
        }
        open(destination); dismiss()
    }
}
