import SwiftUI
import Charts
import AppKit

struct ThesisMapView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: UUID?
    @AppStorage("thesisplus.motion") private var motion = "Subtle"
    var presentation = false
    var openJourney: () -> Void = {}
    var openChapter: (Int) -> Void
    private var chapters: [ChapterFocus] { ThesisMapAnalysis.chapters(store.manuscript, links: store.journeyLinks) }
    private var focused: ChapterFocus? { chapters.first { $0.id == selected } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(presentation ? "THESISPRO • PRESENTATION" : "THE THESIS AT A GLANCE", systemImage: "point.3.connected.trianglepath.dotted").font(.caption.bold()).tracking(1.5).foregroundStyle(.tint)
                    Text(store.manuscript.title).font(.system(size: presentation ? 32 : 25, weight: .medium, design: .serif))
                    Text("\(store.manuscript.degree) • \(store.manuscript.draftWords.formatted()) main-text words • \(chapters.count) mapped chapters").foregroundStyle(.secondary)
                }
                if !presentation {
                    HStack(spacing: 12) {
                        overviewMetric("Manuscript", value: store.manuscript.draftWords.formatted(), caption: "main-text words", icon: "doc.text")
                        overviewMetric("Evidence", value: store.journeyLinks.count.formatted(), caption: "indexed passages", icon: "link")
                        overviewMetric("Review", value: store.journeyLinks.filter { $0.evidenceReviewPending }.count.formatted(), caption: "records to inspect", icon: "text.magnifyingglass")
                    }
                    if let layer = store.languageLayer { LanguageLayerCard(layer: layer) }
                    ContinueWorkCard(read: { if let index = store.selectedChapterIndex { openChapter(index) } }, review: openJourney)
                }
                network
                if let focused {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text(focused.title).font(.title2.bold()); Spacer(); Button("Read chapter") { openChapter(focused.index) }.buttonStyle(.borderedProminent) }
                        Text("\(focused.words.formatted()) words • \(Int((focused.share * 100).rounded()))% of main text • \(focused.balance)").foregroundStyle(.secondary)
                        Text("Concept branches").font(.headline)
                        Text("Headings link to literal manuscript passages, not inferred causal relationships.").font(.caption).foregroundStyle(.secondary)
                        ForEach(store.journeyLinks.filter { $0.chapterIndex == focused.index }.prefix(8)) { link in
                            DisclosureGroup(link.concept) {
                                ConceptChainView(link: link)
                                Button("Edit this chain in Journey") { store.requestedJourneyID = link.id; openJourney() }
                            }
                        }
                        if focused.links > 8 { Text("Showing the first eight concept branches. Journey contains all \(focused.links) indexed passages.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Where the attention goes").font(.title2.bold())
                    Text("Actual words versus the saved chapter budget. A longer chapter is not automatically overdeveloped; a shorter one is not automatically weak.").foregroundStyle(.secondary)
                    Chart(chapters) { chapter in
                        BarMark(x: .value("Words", chapter.words), y: .value("Chapter", "Chapter \(chapter.index + 1)"))
                            .foregroundStyle(Color.accentColor.gradient)
                        if chapter.target > 0 {
                            PointMark(x: .value("Planned words", chapter.target), y: .value("Chapter", "Chapter \(chapter.index + 1)"))
                                .symbol(.diamond).foregroundStyle(.orange).symbolSize(65)
                        }
                    }.frame(height: max(180, CGFloat(chapters.count) * 38)).chartXAxisLabel("Words: bars = actual, diamonds = planned")
                    ForEach(chapters) { chapter in
                        HStack { Text("Chapter \(chapter.index + 1)"); Spacer(); Text(chapter.balance); Text("\(chapter.words.formatted()) / \(chapter.target.formatted())").monospacedDigit() }.font(.callout)
                    }
                    Text("Planning flags use below 80% or above 120% of the saved budget. These are editable-workflow heuristics, not university standards. References and appendices are excluded.").font(.caption).foregroundStyle(.secondary)
                }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 16))
                insights
            }.padding(presentation ? 40 : 24).frame(maxWidth: presentation ? 1250 : 1000)
                .frame(maxWidth: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
            .animation(WorkspaceMotion.animation(motion, reduce: reduceMotion), value: selected)
            .onChange(of: store.activeThesisPROProjectID) { selected = nil }
    }

    private func overviewMetric(_ title: String, value: String, caption: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12)))
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research map").font(.title2.bold())
            Text("Select a chapter to explore its concepts and evidence notes.").foregroundStyle(.secondary)
            GeometryReader { geometry in
                let columns = geometry.size.width > 680 ? 3 : 2
                let cellWidth = geometry.size.width / CGFloat(columns)
                let root = CGPoint(x: geometry.size.width / 2, y: 34)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for (offset, chapter) in chapters.enumerated() {
                            let point = CGPoint(x: (CGFloat(offset % columns) + 0.5) * cellWidth, y: 133 + CGFloat(offset / columns) * 145)
                            var path = Path(); path.move(to: root); path.addLine(to: CGPoint(x: root.x, y: 80)); path.addLine(to: CGPoint(x: point.x, y: 80)); path.addLine(to: point)
                            context.stroke(path, with: .color(.accentColor.opacity(selected == chapter.id ? 0.9 : 0.25)), lineWidth: selected == chapter.id ? 3 : 1.5)
                        }
                    }.accessibilityHidden(true)
                    Label("Research question & argument", systemImage: "sparkle.magnifyingglass").font(.headline)
                        .padding(12).background(.background, in: Capsule()).overlay(Capsule().stroke(.tint.opacity(0.35)))
                        .position(root)
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { offset, chapter in
                        Button { selected = chapter.id } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(chapter.title).font(.system(size: presentation ? 17 : 14, weight: .semibold)).lineLimit(3)
                                Text("\(Int((chapter.share * 100).rounded()))% of text • \(chapter.words.formatted()) words").font(.caption).foregroundStyle(.secondary)
                                Label("\(chapter.missingEvidence) evidence notes missing", systemImage: "circle.dashed").font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .frame(width: cellWidth - 18, height: 126)
                                .background(selected == chapter.id ? Color.accentColor.opacity(0.13) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == chapter.id ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected == chapter.id ? 2 : 1))
                        }.buttonStyle(.plain).position(x: (CGFloat(offset % columns) + 0.5) * cellWidth, y: 155 + CGFloat(offset / columns) * 145)
                    }
                }
            }.frame(height: chapters.count > 6 ? CGFloat((chapters.count + 1) / 2) * 145 + 90 : 530)
            Text("Lines show thesis structure, not verified influence or causal links. Missing notes are documentation gaps, not proof that the underlying passage lacks evidence.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workflow insights", systemImage: "lightbulb").font(.title2.bold())
            if let largest = chapters.max(by: { $0.words < $1.words }) {
                Text("Largest emphasis: \(largest.title), with \(Int((largest.share * 100).rounded()))% of the main text. Check whether this allocation matches your research question before cutting or expanding it.")
            }
            Text("\(store.journeyLinks.filter { $0.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) indexed passages have no evidence note. Start with the chains you mark as priorities, then inspect each source before relying on its claim.")
            Text("\(store.journeyLinks.filter { $0.evidenceReviewPending }.count) passage records still need a scoped evidence review. A populated source note is not approval.")
            Text("\(store.journeyLinks.filter { !AcademicJourney.isCurrent($0, chapters: store.manuscript.chapters) }.count) passage anchors need reconciliation with the current manuscript.")
            Text("Local, rules-based insights. No live AI review, academic quality score or automatic topic-importance judgment is claimed.").font(.caption).foregroundStyle(.secondary)
        }.padding(22).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ThesisReadingView: View {
    @Environment(ProjectStore.self) private var store
    @AppStorage("thesisplus.readingSize") private var size = 19.0
    @AppStorage("thesisplus.readingWidth") private var width = 660.0
    @AppStorage("thesisplus.readingFont") private var typeface = "Serif"
    @AppStorage("thesisplus.warmPaper") private var warm = false
    @Environment(\.colorScheme) private var scheme
    private func moveChapter(_ delta: Int) {
        let next = (store.selectedChapterIndex ?? 0) + delta
        if store.manuscript.chapters.indices.contains(next) { store.selectedChapterID = store.manuscript.chapters[next].id }
    }
    private var design: Font.Design { typeface == "Monospaced" ? .monospaced : typeface == "Sans serif" ? .default : .serif }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Reading room", systemImage: "book.pages").font(.headline)
                Picker("Chapter", selection: Binding(get: { store.selectedChapterID }, set: { store.selectedChapterID = $0 })) {
                    ForEach(store.manuscript.chapters) { Text($0.title).tag(Optional($0.id)) }
                }.frame(maxWidth: 500)
                Spacer()
                Button { moveChapter(-1) } label: { Image(systemName: "chevron.left") }.disabled((store.selectedChapterIndex ?? 0) == 0).help("Previous chapter").accessibilityLabel("Previous chapter")
                Text("\((store.selectedChapterIndex ?? 0) + 1) / \(store.manuscript.chapters.count)").font(.caption.monospacedDigit())
                Button { moveChapter(1) } label: { Image(systemName: "chevron.right") }.disabled((store.selectedChapterIndex ?? 0) >= store.manuscript.chapters.count - 1).help("Next chapter").accessibilityLabel("Next chapter")
                Text("Text size").font(.caption)
                Slider(value: $size, in: 15...28, step: 1).frame(width: 140).accessibilityLabel("Reading text size")
            }.padding(18).background(.bar)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(store.manuscript.title).font(.caption).foregroundStyle(.secondary)
                    Text(store.selectedChapter?.title ?? "Choose a chapter").font(.system(size: size + 10, weight: .medium, design: design))
                    TypesetChapter(text: store.selectedTypesetContent, bodySize: size, typeface: design, pageWidth: width)
                }.frame(maxWidth: width, alignment: .leading).padding(50).frame(maxWidth: .infinity)
            }.background(warm ? (scheme == .dark ? Color(red: 0.16, green: 0.14, blue: 0.11) : Color(red: 0.98, green: 0.95, blue: 0.88)) : Color.accentColor.opacity(0.025))
        }
    }
}
