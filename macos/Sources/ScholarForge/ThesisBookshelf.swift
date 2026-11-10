import AppKit
import ImageIO
import SwiftUI

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
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = (item.title + " " + item.degree + " " + degree(item)).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return (filter == .all || degree(item) == filter.rawValue) && search.split(whereSeparator: \.isWhitespace).allSatisfy { terms.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)) }
    }
    static func artworkName(for id: String) -> String? {
        nil
    }
}

@MainActor private enum LibraryArtwork {
    static let cache: NSCache<NSURL, NSImage> = { let result = NSCache<NSURL, NSImage>(); result.countLimit = 40; return result }()
    static func load(_ item: ThesisPROProjectSummary) -> NSImage? {
        var urls: [URL] = []
        let folder = item.fileURL.deletingLastPathComponent()
        urls.append(folder.appending(path: "bookshelf-artwork.png"))
        if let name = LibraryCatalogue.artworkName(for: item.id) {
            if let url = Bundle.main.url(forResource: name, withExtension: "png") { urls.append(url) }
            if let url = AppResources.url(forResource: name, withExtension: "png") { urls.append(url) }
        }
        urls.append(folder.appending(path: "cover-concept.png"))
        for url in urls {
            if let cached = cache.object(forKey: url as NSURL) { return cached }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { continue }
            let image = NSImage(cgImage: cg, size: .zero)
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        return nil
    }
}

struct LibraryCover: View {
    let item: ThesisPROProjectSummary
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.gradient)
                VStack(spacing: 22) {
                    Image(systemName: "book.closed").font(.largeTitle)
                    Text(item.title).font(.system(size: 22, weight: .medium, design: .serif)).multilineTextAlignment(.center).lineLimit(6)
                    Text(LibraryCatalogue.degree(item)).font(.caption)
                }.foregroundStyle(.white).padding(22)
            }
        }.aspectRatio(2 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Artwork for " + item.title)
            .task(id: item.fileURL) { image = LibraryArtwork.load(item) }
    }
}

struct ThesisBookshelf: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("thesisplus.motion") private var motion = "Subtle"
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var grid = false
    @State private var selectedID: String?
    @State private var visible: [ThesisPROProjectSummary] = []
    @State private var openingError: String?
    var open: (LibraryDestination) -> Void
    private var selected: ThesisPROProjectSummary? { visible.first { $0.id == selectedID } ?? visible.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("ThesisPro", systemImage: "books.vertical").font(.title2.weight(.semibold))
                Spacer()
                Button("Return to workspace", systemImage: "arrow.up.right") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("A library of ideas.").font(.system(size: 32, weight: .medium, design: .serif))
                    Text("Choose a cover. Follow the thinking.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Library layout", selection: $grid) {
                    Text("Carousel").tag(false); Text("Grid").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            HStack {
                TextField("Search titles or degrees", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search library")
                Picker("Degree", selection: $filter) { ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 165)
                Text("\(visible.count) of \(store.thesisPROProjects.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if visible.isEmpty {
                if store.isRefreshingLibrary { Label("Checking the local library…", systemImage: "folder").font(.callout) }
                ContentUnavailableView("No matching theses", systemImage: "books.vertical", description: Text("Try another title or degree. New ThesisPRO projects appear here automatically."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button("Clear filters") { query = ""; filter = .all }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        if grid { gridView } else { carousel }
                    }.padding(8)
                }
                if let selected { detail(selected) }
            }
            if let openingError { Text(openingError).font(.callout).foregroundStyle(.red) }
            HStack {
                Label("Private library on this Mac", systemImage: "lock.shield"); Spacer()
                Text("Artwork is interpretive. Draft length is not submission approval.")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(minWidth: 760, idealWidth: 980, maxWidth: 1150, minHeight: 650, idealHeight: 760)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear { selectedID = store.activeThesisPROProjectID; refresh() }
            .onChange(of: query) { refresh() }
            .onChange(of: filter) { refresh() }
            .onChange(of: store.thesisPROProjects) { refresh() }
    }

    private func refresh() {
        visible = store.thesisPROProjects.filter { LibraryCatalogue.matches($0, query: query, filter: filter) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !visible.contains(where: { $0.id == selectedID }) { selectedID = visible.first?.id }
    }

    private var carousel: some View {
        ScrollViewReader { reader in
            VStack(spacing: 10) {
                HStack {
                    Text("FEATURED COLLECTION").font(.caption2.bold()).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Button("Previous cover", systemImage: "chevron.left") { advance(-1, reader: reader) }.labelStyle(.iconOnly).disabled(visible.count < 2)
                    Text("\((visible.firstIndex { $0.id == selected?.id } ?? 0) + 1) / \(visible.count)").font(.caption.monospacedDigit())
                    Button("Next cover", systemImage: "chevron.right") { advance(1, reader: reader) }.labelStyle(.iconOnly).disabled(visible.count < 2)
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 25) {
                        ForEach(visible) { item in coverButton(item, height: 230).frame(width: 180).id(item.id) }
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private var gridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240))], alignment: .leading, spacing: 22) {
            ForEach(visible) { item in coverButton(item, height: 230) }
        }
    }

    private func coverButton(_ item: ThesisPROProjectSummary, height: CGFloat) -> some View {
        Button { selectedID = item.id; openingError = nil } label: {
            VStack(spacing: 10) {
                LibraryCover(item: item).frame(height: height)
                    .shadow(color: .black.opacity(selected?.id == item.id ? 0.22 : 0.1), radius: 9, x: 3, y: 5)
                Text(item.title).font(.system(size: 14, weight: .medium, design: .serif)).lineLimit(2).frame(height: 38)
                Label(LibraryCatalogue.degree(item), systemImage: selected?.id == item.id ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth: .infinity)
                .background(selected?.id == item.id ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected?.id == item.id ? Color.accentColor.opacity(0.6) : .clear))
                .animation(WorkspaceMotion.animation(motion, reduce: reduceMotion), value: selected?.id)
        }.buttonStyle(.plain).help("Select " + item.title)
            .accessibilityLabel("Select artwork: " + item.title)
    }

    private func advance(_ amount: Int, reader: ScrollViewProxy) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selected?.id } ?? 0
        let next = visible[(index + amount + visible.count) % visible.count].id
        withAnimation(WorkspaceMotion.animation(motion, reduce: reduceMotion)) { selectedID = next; reader.scrollTo(next, anchor: .center) }
    }

    private func detail(_ item: ThesisPROProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title).font(.system(size: 23, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Text("\(LibraryCatalogue.degree(item)) • \(item.draftWords.formatted()) draft words • Review in progress").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Read thesis", systemImage: "book.pages") { route(item, to: .reading) }.buttonStyle(.borderedProminent)
                Button("Explore map", systemImage: "point.3.connected.trianglepath.dotted") { route(item, to: .map) }
                Button("Evidence journey", systemImage: "link") { route(item, to: .journey) }
            }.controlSize(.large)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
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
