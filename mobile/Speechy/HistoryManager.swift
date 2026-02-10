import Foundation

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var records: [TranscriptionRecord] = []

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("transcription_history.json")
    }

    init() {
        load()
    }

    func addRecord(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        save()
    }

    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL)
    }
}
