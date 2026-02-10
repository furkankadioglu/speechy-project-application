import Foundation

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let transcript: String
    let wordCount: Int
    let recordingDuration: TimeInterval
    let transcriptionDuration: TimeInterval

    init(transcript: String, recordingDuration: TimeInterval, transcriptionDuration: TimeInterval) {
        self.id = UUID()
        self.date = Date()
        self.transcript = transcript
        self.wordCount = transcript.split(whereSeparator: { $0.isWhitespace }).count
        self.recordingDuration = recordingDuration
        self.transcriptionDuration = transcriptionDuration
    }
}
