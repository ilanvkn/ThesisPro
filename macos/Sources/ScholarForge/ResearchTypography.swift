import AppKit
import SwiftUI

struct ResearchTable: View {
    let block: String
    private var rows: [[String]] {
        block.split(separator: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }.filter { cells in !cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } }
    }
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text((try? AttributedString(markdown: cell)) ?? AttributedString(cell))
                                .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                                .padding(12).frame(minWidth: 90, maxWidth: 240, alignment: .leading)
                                .background(index == 0 ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(index.isMultiple(of: 2) ? 0.05 : 0.015))
                        }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        }.accessibilityLabel("Research table").textSelection(.enabled)
    }
}

struct LocalResearchImage: View {
    let url: URL
    let caption: String
    @State private var image: NSImage?
    static func path(from block: String) -> URL? {
        guard block.hasPrefix("!["), let split = block.range(of: "]("), block.hasSuffix(")") else { return nil }
        let path = String(block[split.upperBound..<block.index(before: block.endIndex)])
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents/ThesisPRO").resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(root), ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
    static func caption(from block: String) -> String {
        guard let split = block.range(of: "](") else { return "Research figure" }
        return String(block.dropFirst(2).prefix(upTo: split.lowerBound))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image { Image(nsImage: image).resizable().scaledToFit().accessibilityLabel(caption) }
            else { Label("Figure unavailable", systemImage: "photo").foregroundStyle(.secondary) }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.task(id: url) { image = NSImage(contentsOf: url) }
    }
}
