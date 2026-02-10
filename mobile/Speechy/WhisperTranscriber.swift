import SwiftUI
import SwiftWhisper

@MainActor
class WhisperTranscriber: ObservableObject {
    enum TranscriberState {
        case idle
        case loadingModel
        case ready
        case recording
        case transcribing
        case error(String)
    }

    @Published var state: TranscriberState = .idle
    @Published var transcript = ""
    @Published var lastRecordingDuration: TimeInterval?
    @Published var lastTranscriptionDuration: TimeInterval?
    @Published var lastWordCount: Int?

    private var whisper: Whisper?
    private let recorder = AudioRecorderEngine()
    private let downloadManager = ModelDownloadManager.shared
    private var recordingStartTime: Date?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = state { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }

    func loadModelIfNeeded() async {
        guard whisper == nil else {
            state = .ready
            return
        }
        guard downloadManager.isModelReady else { return }

        state = .loadingModel
        let fileURL = downloadManager.modelFilePath
        do {
            let w = try await Task.detached(priority: .userInitiated) {
                let params = WhisperParams(strategy: .greedy)
                params.language = .turkish
                params.n_threads = Int32(min(ProcessInfo.processInfo.activeProcessorCount, 6))

                // Decoding: single pass (5x speedup, minimal quality loss)
                params.greedy.best_of = 1

                // Skip unnecessary tokens
                params.suppress_blank = true
                params.suppress_non_speech_tokens = true

                // Disable logging
                params.print_progress = false
                params.print_realtime = false
                params.print_timestamps = false
                params.print_special = false

                return Whisper(fromFileURL: fileURL, withParams: params)
            }.value
            whisper = w
            state = .ready
        } catch {
            state = .error("Model yüklenemedi: \(error.localizedDescription)")
        }
    }

    func toggleRecording() {
        if isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        transcript = ""
        lastRecordingDuration = nil
        lastTranscriptionDuration = nil
        lastWordCount = nil
        do {
            try recorder.startRecording()
            recordingStartTime = Date()
            state = .recording
        } catch {
            state = .error("Kayıt başlatılamadı: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe() {
        let rawFrames = recorder.stopRecording()
        let recordingDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        lastRecordingDuration = recordingDuration

        guard !rawFrames.isEmpty else {
            state = .ready
            return
        }

        guard let whisper else {
            state = .error("Model yüklü değil")
            return
        }

        let frames = Self.trimSilence(from: rawFrames)

        guard !frames.isEmpty else {
            state = .ready
            return
        }

        state = .transcribing
        let transcriptionStart = Date()

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let segments = try await whisper.transcribe(audioFrames: frames)
                let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
                let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
                await MainActor.run {
                    self?.transcript = text
                    self?.lastTranscriptionDuration = transcriptionDuration
                    self?.lastWordCount = wordCount
                    self?.state = .ready

                    if !text.isEmpty {
                        let record = TranscriptionRecord(
                            transcript: text,
                            recordingDuration: recordingDuration,
                            transcriptionDuration: transcriptionDuration
                        )
                        HistoryManager.shared.addRecord(record)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.state = .error("Dönüştürme hatası: \(error.localizedDescription)")
                }
            }
        }
    }

    func clearTranscript() {
        transcript = ""
        if case .error = state {
            state = .ready
        }
    }

    // MARK: - Audio Processing

    /// Trim leading and trailing silence to reduce whisper processing time.
    /// Uses RMS energy over 100ms windows at 16kHz.
    static func trimSilence(from frames: [Float], threshold: Float = 0.008, windowSize: Int = 1600) -> [Float] {
        guard frames.count > windowSize else { return frames }

        let stepCount = frames.count / windowSize

        // Find first window above threshold
        var startWindow = 0
        for i in 0..<stepCount {
            let offset = i * windowSize
            let end = min(offset + windowSize, frames.count)
            var sumSq: Float = 0
            for j in offset..<end { sumSq += frames[j] * frames[j] }
            let rms = (sumSq / Float(end - offset)).squareRoot()
            if rms > threshold {
                startWindow = i
                break
            }
        }

        // Find last window above threshold
        var endWindow = stepCount - 1
        for i in stride(from: stepCount - 1, through: 0, by: -1) {
            let offset = i * windowSize
            let end = min(offset + windowSize, frames.count)
            var sumSq: Float = 0
            for j in offset..<end { sumSq += frames[j] * frames[j] }
            let rms = (sumSq / Float(end - offset)).squareRoot()
            if rms > threshold {
                endWindow = i
                break
            }
        }

        // Keep one window of padding on each side
        let start = max(0, (startWindow - 1) * windowSize)
        let end = min(frames.count, (endWindow + 2) * windowSize)

        guard start < end else { return frames }
        return Array(frames[start..<end])
    }
}
