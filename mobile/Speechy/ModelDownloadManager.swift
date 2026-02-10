import Foundation

@MainActor
class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case error(String)
    }

    @Published var state: State = .notDownloaded

    // Local name is "ggml-small.bin" so whisper.cpp looks for "ggml-small-encoder.mlmodelc" (CoreML)
    private let modelFileName = "ggml-small.bin"
    private let coreMLModelName = "ggml-small-encoder.mlmodelc"
    private let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin")!

    var modelFilePath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(modelFileName)
    }

    var coreMLModelPath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(coreMLModelName)
    }

    var isModelReady: Bool {
        FileManager.default.fileExists(atPath: modelFilePath.path)
    }

    private var downloadTask: URLSessionDownloadTask?

    func checkModel() {
        cleanupOldModel()
        if isModelReady {
            copyCoreMLModelIfNeeded()
            state = .downloaded
        } else {
            state = .notDownloaded
        }
    }

    private func cleanupOldModel() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["ggml-medium-q5_0.bin", "ggml-base.bin", "ggml-small-q5_1.bin"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
        }
    }

    /// Copy bundled CoreML encoder model to Documents directory (next to .bin model)
    func copyCoreMLModelIfNeeded() {
        let dest = coreMLModelPath
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        guard let bundlePath = Bundle.main.path(forResource: "ggml-small-encoder", ofType: "mlmodelc") else { return }
        try? FileManager.default.copyItem(atPath: bundlePath, toPath: dest.path)
    }

    func startDownload() {
        guard !isModelReady else {
            state = .downloaded
            return
        }
        state = .downloading(progress: 0)
        let delegate = DownloadDelegate(manager: self)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        let task = session.downloadTask(with: modelURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .notDownloaded
    }

    func deleteModel() {
        try? FileManager.default.removeItem(at: modelFilePath)
        try? FileManager.default.removeItem(at: coreMLModelPath)
        state = .notDownloaded
    }

    // MARK: - Download Delegate

    func handleDownloadProgress(_ progress: Double) {
        state = .downloading(progress: progress)
    }

    func handleDownloadComplete(tempURL: URL?, error: Error?) {
        downloadTask = nil
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        guard let tempURL else {
            state = .error("İndirme başarısız oldu")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: modelFilePath.path) {
                try FileManager.default.removeItem(at: modelFilePath)
            }
            try FileManager.default.moveItem(at: tempURL, to: modelFilePath)
            copyCoreMLModelIfNeeded()
            state = .downloaded
        } catch {
            state = .error("Model dosyası kaydedilemedi: \(error.localizedDescription)")
        }
    }
}

// Separate class since NSObject + URLSessionDownloadDelegate can't be @MainActor
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: ModelDownloadManager?

    init(manager: ModelDownloadManager) {
        self.manager = manager
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        try? FileManager.default.copyItem(at: location, to: tempCopy)
        Task { @MainActor [weak self] in
            self?.manager?.handleDownloadComplete(tempURL: tempCopy, error: nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task { @MainActor [weak self] in
                self?.manager?.handleDownloadComplete(tempURL: nil, error: error)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak self] in
            self?.manager?.handleDownloadProgress(progress)
        }
    }
}
