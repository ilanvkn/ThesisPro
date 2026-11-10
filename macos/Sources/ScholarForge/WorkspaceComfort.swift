import SwiftUI
import Foundation
import CryptoKit

enum WorkspaceMotion {
    static func animation(_ mode: String, reduce: Bool) -> Animation? {
        guard !reduce, mode != "Off" else { return nil }
        return mode == "Full" ? .spring(response: 0.45, dampingFraction: 0.85) : .easeInOut(duration: 0.16)
    }
}

enum ReadingHistory {
    static func fingerprints(_ chapters: [ManuscriptChapter]) -> [String: String] {
        Dictionary(chapters.enumerated().map { index, chapter in
            ("\(index):\(chapter.title)", SHA256.hash(data: Data(chapter.content.utf8)).map { String(format: "%02x", $0) }.joined())
        }, uniquingKeysWith: { _, last in last })
    }
    static func changed(_ old: [String: String], _ new: [String: String]) -> Int {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.count
    }
}

struct WorkspacePreferences: View {
    @AppStorage("thesisplus.appearance") private var appearance = "Light"
    @AppStorage("thesisplus.readingSize") private var size = 19.0
    @AppStorage("thesisplus.readingWidth") private var width = 660.0
    @AppStorage("thesisplus.readingFont") private var font = "Serif"
    @AppStorage("thesisplus.warmPaper") private var warm = false
    @AppStorage("thesisplus.motion") private var motion = "Subtle"
    @AppStorage("thesisplus.showInspector") private var inspector = true
    @AppStorage("thesisplus.showLibraryAtLaunch") private var library = true
    var body: some View {
        Form {
            Section("Your workspace") {
                Picker("Appearance", selection: $appearance) { ForEach(["Light", "Dark", "System"], id: \.self) { Text($0) } }
                Picker("Motion", selection: $motion) { ForEach(["Off", "Subtle", "Full"], id: \.self) { Text($0) } }
                Text("System Reduce Motion always takes priority. Motion follows interaction, never simulated AI activity.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show guidance panel", isOn: $inspector)
                Toggle("Open bookshelf at launch", isOn: $library)
            }
            Section("Reading room") {
                Picker("Typeface", selection: $font) { ForEach(["Serif", "Sans serif", "Monospaced"], id: \.self) { Text($0) } }
                LabeledContent("Text size: \(Int(size))") { Slider(value: $size, in: 15...28, step: 1) }
                LabeledContent("Page width: \(Int(width))") { Slider(value: $width, in: 480...900, step: 20) }
                Toggle("Warm paper", isOn: $warm)
                Text("These preferences change your reading workspace, not the submitted document or its print formatting.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 510, height: 470)
    }
}

struct ContinueWorkCard: View {
    @Environment(ProjectStore.self) private var store
    var read: () -> Void
    var review: () -> Void
    private var next: JourneyLink? {
        store.journeyLinks.first { $0.priority && $0.missingCount > 0 } ?? store.journeyLinks.first { $0.missingCount > 0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Continue my work", systemImage: "bookmark").font(.headline)
            HStack {
                Text(store.selectedChapter?.title ?? "Choose a chapter").font(.system(size: 20, design: .serif))
                Spacer(); Button("Resume reading", action: read).buttonStyle(.borderedProminent)
            }
            Text(store.continuityMessage).font(.caption).foregroundStyle(.secondary)
            if let next {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next working question: \(next.concept)").font(.callout.bold())
                        Text(next.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Which inspected source supports this passage, and where?" : "What decision follows from this passage, and under what limitations?").font(.callout)
                    }
                    Spacer()
                    Button("Inspect chain") { store.requestedJourneyID = next.id; review() }
                }
            }
            Text("A missing working note is a review prompt, not a verdict on the thesis.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ConceptChainView: View {
    let link: JourneyLink
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage("thesisplus.motion") private var motion = "Subtle"
    @State private var stage = 0
    private let labels = ["Concept", "Passage", "Evidence", "Decision", "Limitation"]
    private var values: [String] { [link.concept, link.passage, link.evidence, link.decision, link.limitation] }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(0..<labels.count, id: \.self) { index in
                        if index > 0 { Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true) }
                        Button { stage = index } label: {
                            Label(labels[index], systemImage: values[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "circle.dashed" : "circle.fill")
                                .font(.caption.bold()).padding(10)
                                .background(stage == index ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06), in: Capsule())
                                .overlay(Capsule().stroke(stage == index ? Color.accentColor : .clear))
                        }.buttonStyle(.plain)
                    }
                }.padding(3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(labels[stage]).font(.headline)
                Text(values[stage].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No working note recorded yet. Inspect the original passage and sources in Journey before completing this link." : values[stage]).textSelection(.enabled)
            }.id(stage).transition(.opacity).frame(maxWidth: .infinity, alignment: .leading)
            Text("Connections show the working argument, not proven causation. Filled nodes mean recorded notes, not verified evidence.").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).animation(WorkspaceMotion.animation(motion, reduce: reduce), value: stage)
    }
}
