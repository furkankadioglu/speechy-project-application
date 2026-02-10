import SwiftUI

struct ContentView: View {
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var transcriber = WhisperTranscriber()
    @State private var showCopied = false

    var body: some View {
        Group {
            if case .downloaded = downloadManager.state {
                TabView {
                    VStack(spacing: 20) {
                        transcriptionView
                    }
                    .padding()
                    .tabItem {
                        Label("Kayıt", systemImage: "mic.fill")
                    }

                    HistoryView()
                        .tabItem {
                            Label("Geçmiş", systemImage: "clock.fill")
                        }
                }
            } else {
                VStack(spacing: 20) {
                    modelDownloadView
                }
                .padding()
            }
        }
        .onAppear {
            downloadManager.checkModel()
        }
        .onReceive(downloadManager.$state) { newState in
            if case .downloaded = newState {
                Task { await transcriber.loadModelIfNeeded() }
            }
        }
    }

    // MARK: - Model Download View

    @ViewBuilder
    private var modelDownloadView: some View {
        Spacer()

        Image(systemName: "arrow.down.circle")
            .font(.system(size: 60))
            .foregroundStyle(.blue)

        Text("Whisper Model Gerekli")
            .font(.title2.bold())

        Text("Konuşma tanıma için model indirilmesi gerekiyor (~181 MB)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        switch downloadManager.state {
        case .notDownloaded:
            Button("Modeli İndir") {
                downloadManager.startDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text("İndiriliyor...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button("İptal", role: .destructive) {
                    downloadManager.cancelDownload()
                }
                .font(.caption)
            }

        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
            Button("Tekrar Dene") {
                downloadManager.startDownload()
            }
            .buttonStyle(.borderedProminent)

        case .downloaded:
            EmptyView()
        }

        Spacer()
    }

    // MARK: - Transcription View

    @ViewBuilder
    private var transcriptionView: some View {
        // Header
        HStack {
            Text("Speechy")
                .font(.largeTitle.bold())
            Spacer()
            if !transcriber.transcript.isEmpty {
                Button {
                    UIPasteboard.general.string = transcriber.transcript
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Label(showCopied ? "Kopyalandı!" : "Kopyala",
                          systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                }

                Button {
                    transcriber.clearTranscript()
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                }
                .tint(.red)
            }
        }

        // Status
        if case .loadingModel = transcriber.state {
            HStack(spacing: 8) {
                ProgressView()
                Text("Model yükleniyor...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // Transcription area
        ScrollView {
            Text(transcriptionPlaceholder)
                .foregroundStyle(transcriber.transcript.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // Error
        if let error = transcriber.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
        }

        // Timing info
        if let recDur = transcriber.lastRecordingDuration,
           let transDur = transcriber.lastTranscriptionDuration {
            VStack(spacing: 4) {
                HStack(spacing: 16) {
                    Label(String(format: "Kayıt: %.1f sn", recDur),
                          systemImage: "mic")
                    Label(String(format: "Çeviri: %.1f sn", transDur),
                          systemImage: "text.badge.checkmark")
                }
                if let wordCount = transcriber.lastWordCount, wordCount > 0 {
                    Label("\(wordCount) kelime", systemImage: "text.word.spacing")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        // Record button
        Button {
            transcriber.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(transcriber.isRecording
                          ? Color.red.opacity(0.15)
                          : Color.blue.opacity(0.1))
                    .frame(width: 100, height: 100)
                if transcriber.isTranscribing {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: transcriber.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(transcriber.isRecording ? .red : .blue)
                }
            }
        }
        .disabled(!isRecordButtonEnabled)

        Text(recordButtonLabel)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var transcriptionPlaceholder: String {
        if transcriber.isTranscribing {
            return "Dönüştürülüyor..."
        }
        return transcriber.transcript.isEmpty
            ? "Konuşmaya başlamak için butona basın..."
            : transcriber.transcript
    }

    private var isRecordButtonEnabled: Bool {
        switch transcriber.state {
        case .ready, .recording: return true
        default: return false
        }
    }

    private var recordButtonLabel: String {
        switch transcriber.state {
        case .recording: return "Dinliyor..."
        case .transcribing: return "Dönüştürülüyor..."
        case .loadingModel: return "Model yükleniyor..."
        default: return "Kayıt Başlat"
        }
    }
}
