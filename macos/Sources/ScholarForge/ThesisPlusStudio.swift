import AppKit
import CoreText
import PDFKit
import SwiftUI
import UniformTypeIdentifiers


struct TypesetChapter: View {
    let text: String
    var bodySize: Double = 16
    var typeface: Font.Design = .serif
    var pageWidth: Double = 660
    private var blocks: [String] { text.components(separatedBy: "\n\n").filter { !$0.isEmpty } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if let figure = ManuscriptFigure(block) {
                    ManuscriptFigureView(figure: figure)
                } else if block.hasPrefix("#") || (block.count < 170 && block.range(of: #"^\d+\.\d+\s"#, options: .regularExpression) != nil && !block.contains("\n")) {
                    Text(block.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
                        .font(.system(size: bodySize + 5, weight: .semibold, design: typeface)).padding(.top, 12)
                } else {
                    Text(block).font(.system(size: bodySize, design: typeface)).lineSpacing(bodySize * 0.44)
                }
            }
        }.textSelection(.enabled).frame(maxWidth: pageWidth, alignment: .leading)
    }
}

struct ManuscriptFigure: Hashable {
    let label: String
    let url: URL
    let pageIndex: Int

    init?(_ block: String) {
        guard block.hasPrefix("!["), let divider = block.range(of: "]("), block.hasSuffix(")"),
              let marker = block.range(of: "#page=", options: .backwards),
              let page = Int(block[marker.upperBound..<block.index(before: block.endIndex)]), page > 0 else { return nil }
        let path = String(block[divider.upperBound..<marker.lowerBound])
        let candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/ThesisPRO").resolvingSymlinksInPath().path + "/"
        guard candidate.path.hasPrefix(root), candidate.pathExtension.lowercased() == "pdf" else { return nil }
        label = String(block[block.index(block.startIndex, offsetBy: 2)..<divider.lowerBound])
        url = candidate; pageIndex = page - 1
    }

    struct LoadedPage {
        let document: PDFDocument
        let page: PDFPage
    }

    func loadPage() -> LoadedPage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: pageIndex) else { return nil }
        // Exclude the figure-pack heading and folio, retaining artwork, caption and source.
        page.setBounds(CGRect(x: 100, y: 65, width: 435, height: 680), for: .cropBox)
        return LoadedPage(document: document, page: page)
    }
}

struct ManuscriptFigureView: View {
    let figure: ManuscriptFigure
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit().accessibilityLabel(figure.label)
            } else { Text("Figure unavailable: \(figure.label)").foregroundStyle(.secondary) }
        }.task(id: figure) {
            thumbnail = figure.loadPage()?.page.thumbnail(of: NSSize(width: 900, height: 1407), for: .cropBox)
        }
    }
}

@MainActor
enum ThesisPDFRenderer {
    static func render(_ manuscript: ManuscriptProject) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        var pageNumber = 0
        func draw(_ attributed: NSAttributedString, numbered: Bool = true) {
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            var start = 0
            while start < attributed.length {
                context.beginPDFPage(nil)
                pageNumber += 1
                let area = CGPath(rect: CGRect(x: 65, y: 60, width: 476, height: 718), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), area, nil)
                CTFrameDraw(frame, context)
                let range = CTFrameGetVisibleStringRange(frame)
                if numbered {
                    let footer = NSAttributedString(string: "\(pageNumber)", attributes: [.font: NSFont(name: "Times New Roman", size: 10) ?? NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
                    let line = CTLineCreateWithAttributedString(footer)
                    context.textPosition = CGPoint(x: (595 - CTLineGetTypographicBounds(line, nil, nil, nil)) / 2, y: 30)
                    CTLineDraw(line, context)
                }
                context.endPDFPage()
                if range.length == 0 { break }
                start += range.length
            }
        }
        let style = NSMutableParagraphStyle(); style.lineSpacing = 4; style.paragraphSpacing = 12
        let body: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12), .paragraphStyle: style, .foregroundColor: NSColor.black]
        var heading = body; heading[.font] = NSFont.boldSystemFont(ofSize: 20)
        let front = NSMutableAttributedString(string: manuscript.title + "\n\n", attributes: heading)
        let enteredAuthor = manuscript.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorLine = enteredAuthor == "Researcher" ? "" : enteredAuthor
        front.append(NSAttributedString(string: (authorLine.isEmpty ? "" : authorLine + "\n\n") + manuscript.degree, attributes: body))
        let titleStyle = NSMutableParagraphStyle(); titleStyle.alignment = .center; titleStyle.paragraphSpacing = 24
        front.addAttribute(.paragraphStyle, value: titleStyle, range: NSRange(location: 0, length: front.length))
        draw(front, numbered: false)
        var chapterPages: [[(text: NSAttributedString?, figure: ManuscriptFigure.LoadedPage?)]] = []
        for chapter in manuscript.chapters {
            var parts: [(text: NSAttributedString?, figure: ManuscriptFigure.LoadedPage?)] = []
            var page = NSMutableAttributedString(string: chapter.title + "\n\n", attributes: heading)
            for block in chapter.content.components(separatedBy: "\n\n") {
                if let figure = ManuscriptFigure(block), let figurePage = figure.loadPage() {
                    if page.length > 0 { parts.append((page.copy() as? NSAttributedString, nil)) }
                    parts.append((nil, figurePage))
                    page = NSMutableAttributedString(string: "")
                    continue
                }
                let isHeading = block.hasPrefix("#") || (block.count < 170 && block.range(of: #"^\d+\.\d+\s"#, options: .regularExpression) != nil && !block.contains("\n"))
                var attributes = body
                if isHeading { attributes[.font] = NSFont.boldSystemFont(ofSize: 14) }
                page.append(NSAttributedString(string: block.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) + "\n\n", attributes: attributes))
            }
            if page.length > 0 { parts.append((page, nil)) }
            chapterPages.append(parts)
        }
        func pageCount(_ attributed: NSAttributedString) -> Int {
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let area = CGPath(rect: CGRect(x: 65, y: 60, width: 476, height: 718), transform: nil)
            var offset = 0; var count = 0
            while offset < attributed.length {
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), area, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                offset += visible.length; count += 1
            }
            return count
        }
        if !chapterPages.isEmpty {
            let chapterCounts = chapterPages.map { parts in parts.reduce(0) { $0 + ($1.text.map(pageCount) ?? 1) } }
            var contentsCount = 1
            var contents = NSMutableAttributedString(string: "")
            for _ in 0..<10 {
                contents = NSMutableAttributedString(string: "Contents\n\n", attributes: heading)
                var firstPage = pageNumber + contentsCount + 1
                for (index, chapter) in manuscript.chapters.enumerated() {
                    contents.append(NSAttributedString(string: "\(chapter.title)    \(firstPage)\n\n", attributes: body))
                    firstPage += chapterCounts[index]
                }
                let measured = pageCount(contents)
                if measured == contentsCount { break }
                contentsCount = measured
            }
            draw(contents)
        }
        for parts in chapterPages {
            for part in parts {
                if let text = part.text { draw(text) }
                else if let loaded = part.figure {
                    let figure = loaded.page
                    context.beginPDFPage(nil); pageNumber += 1
                    context.saveGState()
                    let bounds = figure.bounds(for: .cropBox)
                    let scale = min(411 / bounds.width, 680 / bounds.height)
                    context.translateBy(x: 113, y: 85)
                    context.scaleBy(x: scale, y: scale)
                    figure.draw(with: .cropBox, to: context)
                    context.restoreGState()
                    let footer = CTLineCreateWithAttributedString(NSAttributedString(string: "\(pageNumber)", attributes: body))
                    context.textPosition = CGPoint(x: (595 - CTLineGetTypographicBounds(footer, nil, nil, nil)) / 2, y: 30)
                    CTLineDraw(footer, context)
                    context.endPDFPage()
                }
            }
        }
        context.closePDF()
        return data as Data
    }
}

struct PDFReadingView: NSViewRepresentable {
    let data: Data
    final class Coordinator { var loaded = Data() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        context.coordinator.loaded = data
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if context.coordinator.loaded != data {
            view.document = PDFDocument(data: data)
            context.coordinator.loaded = data
            view.autoScales = true
        }
    }
}

struct PDFPreviewPayload: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}

struct PDFCopy: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ThesisPDFSheet: View {
    let data: Data
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var errorMessage: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) { Text("PDF reading copy").font(.headline); Text("Working draft • not submission-approved").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Save PDF…", systemImage: "square.and.arrow.down") { exporting = true }.buttonStyle(.borderedProminent)
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            PDFReadingView(data: data)
        }.frame(minWidth: 800, minHeight: 680)
            .fileExporter(isPresented: $exporting, document: PDFCopy(data: data), contentType: .pdf, defaultFilename: title) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("PDF export", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }
}
