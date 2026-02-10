import SwiftUI

struct HistoryView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @State private var copiedId: UUID?

    var body: some View {
        NavigationView {
            Group {
                if historyManager.records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Henüz kayıt yok")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(historyManager.records) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                // Date + copy button
                                HStack {
                                    Text(record.date, style: .date)
                                    Text(record.date, style: .time)
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = record.transcript
                                        copiedId = record.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            if copiedId == record.id { copiedId = nil }
                                        }
                                    } label: {
                                        Image(systemName: copiedId == record.id ? "checkmark" : "doc.on.doc")
                                            .font(.caption)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                // Transcript
                                Text(record.transcript)
                                    .font(.body)
                                    .lineLimit(3)

                                // Timing + word count
                                HStack(spacing: 12) {
                                    Label(formatDuration(record.recordingDuration),
                                          systemImage: "mic")
                                    Label(formatDuration(record.transcriptionDuration),
                                          systemImage: "text.badge.checkmark")
                                    Label("\(record.wordCount) kelime",
                                          systemImage: "text.word.spacing")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { historyManager.records[$0].id }
                            ids.forEach { historyManager.deleteRecord(id: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Geçmiş")
            .toolbar {
                if !historyManager.records.isEmpty {
                    Button("Tümünü Sil", role: .destructive) {
                        historyManager.clearAll()
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        String(format: "%.1f sn", seconds)
    }
}
