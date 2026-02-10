import XCTest
@testable import Speechy

@MainActor
final class ModelDownloadManagerTests: XCTestCase {

    var manager: ModelDownloadManager!

    override func setUp() {
        super.setUp()
        manager = ModelDownloadManager.shared
        // Temiz başla
        manager.deleteModel()
    }

    override func tearDown() {
        manager.deleteModel()
        manager = nil
        super.tearDown()
    }

    // MARK: - Model Path

    func testModelFilePathIsInDocumentsDirectory() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        XCTAssertTrue(manager.modelFilePath.path.hasPrefix(docs.path))
    }

    func testModelFilePathContainsCorrectFileName() {
        XCTAssertTrue(manager.modelFilePath.lastPathComponent == "ggml-small.bin")
    }

    // MARK: - checkModel

    func testCheckModelSetsNotDownloadedWhenNoFile() {
        manager.checkModel()
        XCTAssertEqual(manager.state, .notDownloaded)
    }

    func testCheckModelSetsDownloadedWhenFileExists() throws {
        // Sahte dosya oluştur
        try Data("test".utf8).write(to: manager.modelFilePath)
        manager.checkModel()
        XCTAssertEqual(manager.state, .downloaded)
    }

    // MARK: - isModelReady

    func testIsModelReadyReturnsFalseWhenNoFile() {
        XCTAssertFalse(manager.isModelReady)
    }

    func testIsModelReadyReturnsTrueWhenFileExists() throws {
        try Data("test".utf8).write(to: manager.modelFilePath)
        XCTAssertTrue(manager.isModelReady)
    }

    // MARK: - startDownload (guard path)

    func testStartDownloadSetsDownloadedIfModelExists() throws {
        try Data("test".utf8).write(to: manager.modelFilePath)
        manager.startDownload()
        XCTAssertEqual(manager.state, .downloaded)
    }

    // MARK: - cancelDownload

    func testCancelDownloadResetsState() {
        manager.state = .downloading(progress: 0.5)
        manager.cancelDownload()
        XCTAssertEqual(manager.state, .notDownloaded)
    }

    // MARK: - deleteModel

    func testDeleteModelRemovesFileAndResetsState() throws {
        try Data("test".utf8).write(to: manager.modelFilePath)
        XCTAssertTrue(manager.isModelReady)

        manager.deleteModel()

        XCTAssertFalse(manager.isModelReady)
        XCTAssertEqual(manager.state, .notDownloaded)
    }

    func testDeleteModelSafeWhenNoFile() {
        manager.deleteModel()
        XCTAssertEqual(manager.state, .notDownloaded)
    }

    // MARK: - handleDownloadComplete

    func testHandleDownloadCompleteWithErrorSetsErrorState() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test hatası"])
        manager.handleDownloadComplete(tempURL: nil, error: error)
        if case .error(let msg) = manager.state {
            XCTAssertTrue(msg.contains("Test hatası"))
        } else {
            XCTFail("State should be .error")
        }
    }

    func testHandleDownloadCompleteWithNilURLSetsError() {
        manager.handleDownloadComplete(tempURL: nil, error: nil)
        if case .error(let msg) = manager.state {
            XCTAssertEqual(msg, "İndirme başarısız oldu")
        } else {
            XCTFail("State should be .error")
        }
    }

    func testHandleDownloadCompleteWithValidFileSetsDownloaded() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        try Data("model-data".utf8).write(to: tempFile)

        manager.handleDownloadComplete(tempURL: tempFile, error: nil)

        XCTAssertEqual(manager.state, .downloaded)
        XCTAssertTrue(manager.isModelReady)
    }

    // MARK: - handleDownloadProgress

    func testHandleDownloadProgressUpdatesState() {
        manager.handleDownloadProgress(0.42)
        XCTAssertEqual(manager.state, .downloading(progress: 0.42))
    }

    // MARK: - State Equatable

    func testStateEquatable() {
        XCTAssertEqual(ModelDownloadManager.State.notDownloaded, .notDownloaded)
        XCTAssertEqual(ModelDownloadManager.State.downloaded, .downloaded)
        XCTAssertEqual(ModelDownloadManager.State.downloading(progress: 0.5), .downloading(progress: 0.5))
        XCTAssertNotEqual(ModelDownloadManager.State.downloading(progress: 0.5), .downloading(progress: 0.7))
        XCTAssertEqual(ModelDownloadManager.State.error("a"), .error("a"))
        XCTAssertNotEqual(ModelDownloadManager.State.error("a"), .error("b"))
    }
}
