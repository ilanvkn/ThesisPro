import SwiftUI

struct LanguageLayerCard: View {
    let layer: LanguageLayer
    @State private var showDraft = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pengolahan Bahasa Malaysia", systemImage: "character.book.closed").font(.title2.bold())
            ProgressView(value: layer.coverage) {
                Text("Draf BM baharu: \(Int(layer.coverage * 100))% • \(layer.valid ? layer.sourceWords : 0) / \(layer.baselineWords) perkataan sumber")
            }
            ProgressView(value: layer.reviewed) { Text("Semakan akhir BM: \(Int(layer.reviewed * 100))%") }
            Text(layer.scope).font(.callout)
            Text("Kemajuan manuskrip asal dikekalkan. Liputan bahasa bukan pengesahan kesahan kajian.").font(.caption).foregroundStyle(.secondary)
            if !layer.valid { Label("Sumber atau draf berubah. Kredit kemajuan ditangguhkan sehingga disemak semula.", systemImage: "exclamationmark.triangle") }
            DisclosureGroup("Baki pengesahan akademik") { Text(layer.blockers).font(.callout).padding(.top, 8) }
            Button("Baca draf BM") { showDraft = true }.disabled(layer.text.isEmpty)
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showDraft) {
            VStack {
                HStack { Text("Bab 5 • Draf pengolahan BM, belum muktamad").font(.headline); Spacer(); Button("Tutup") { showDraft = false } }.padding()
                ScrollView { TypesetChapter(text: layer.text).padding(30) }
            }.frame(minWidth: 760, minHeight: 600)
        }
    }
}
